import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";

Deno.serve(async (req) => {
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );

  try {
    console.log("Starting streak maintenance job at", new Date().toISOString());

    // Find users with active streaks that should be expired
    const { data: expiredStreaks, error: queryError } = await supabaseAdmin
      .from("user_streaks")
      .select(`
        user_id,
        current_streak,
        last_goal_timestamp,
        grace_period_hours
      `)
      .gt("current_streak", 0)
      .not("last_goal_timestamp", "is", null);

    if (queryError) {
      console.error("Error querying expired streaks:", queryError);
      return new Response(JSON.stringify({ error: "Database query failed" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    console.log(
      `Found ${expiredStreaks?.length || 0} users with active streaks to check`
    );

    let expiredCount = 0;
    const expiredUserIds: string[] = [];
    const currentTime = new Date();

    if (expiredStreaks && expiredStreaks.length > 0) {
      // Check each user's streak for expiration
      for (const streak of expiredStreaks) {
        const lastGoalTime = new Date(streak.last_goal_timestamp);
        const gracePeriodHours = streak.grace_period_hours || 4;
        const expirationTime = new Date(
          lastGoalTime.getTime() + (24 + gracePeriodHours) * 60 * 60 * 1000
        );

        if (currentTime > expirationTime) {
          expiredUserIds.push(streak.user_id);
          expiredCount++;
          console.log(
            `Streak expired for user ${
              streak.user_id
            }: last goal at ${lastGoalTime.toISOString()}, expired at ${expirationTime.toISOString()}`
          );
        }
      }

      // Batch update expired streaks
      if (expiredUserIds.length > 0) {
        const { error: updateError } = await supabaseAdmin
          .from("user_streaks")
          .update({
            current_streak: 0,
            updated_at: new Date().toISOString(),
          })
          .in("user_id", expiredUserIds);

        if (updateError) {
          console.error("Error updating expired streaks:", updateError);
          return new Response(
            JSON.stringify({
              error: "Failed to update expired streaks",
              details: updateError,
            }),
            {
              status: 500,
              headers: { "Content-Type": "application/json" },
            }
          );
        }

        console.log(`Successfully broke ${expiredCount} expired streaks`);
      }
    }

    // Optional: Clean up old daily_protein_totals records (keep last 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const { error: cleanupError } = await supabaseAdmin
      .from("daily_protein_totals")
      .delete()
      .lt("date", thirtyDaysAgo.toISOString().split("T")[0]);

    if (cleanupError) {
      console.error("Error cleaning up old daily totals:", cleanupError);
      // Don't fail the request for cleanup errors
    } else {
      console.log("Cleaned up daily totals older than 30 days");
    }

    const result = {
      success: true,
      timestamp: currentTime.toISOString(),
      totalUsersChecked: expiredStreaks?.length || 0,
      expiredStreaksCount: expiredCount,
      expiredUserIds: expiredUserIds,
      message: `Streak maintenance completed. ${expiredCount} streaks expired.`,
    };

    console.log("Streak maintenance job completed:", result);

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    console.error("Streak maintenance job failed:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error.message,
        timestamp: new Date().toISOString(),
      }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
