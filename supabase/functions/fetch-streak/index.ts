import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization")!;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  try {
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
    } = await supabase.auth.getUser(token);

    // Get current streak data from our simple streak system
    const { data: streakData, error: streakError } = await supabase
      .from('user_streaks')
      .select('current_streak, max_streak, last_goal_date')
      .eq('user_id', user.id)
      .single();

    if (streakError && streakError.code !== 'PGRST116') { // PGRST116 = no rows returned
      console.error("Streak query error:", streakError);
      return new Response(JSON.stringify({ error: "Failed to fetch streak" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Get recent daily totals for streak history
    const { data: historyData, error: historyError } = await supabase
      .from('daily_protein_totals')
      .select('date, total_protein, goal_met')
      .eq('user_id', user.id)
      .order('date', { ascending: false })
      .limit(30);

    if (historyError) {
      console.error("History query error:", historyError);
    }

    const response = {
      length: streakData?.current_streak || 0,
      maxStreak: streakData?.max_streak || 0,
      lastGoalDate: streakData?.last_goal_date || null,
      streakHistory: historyData || [],
    };

    return new Response(
      JSON.stringify(response),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: "Internal server error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
