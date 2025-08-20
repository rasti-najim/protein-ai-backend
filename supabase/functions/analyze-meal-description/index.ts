import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";
import OpenAI from "jsr:@openai/openai";
import { z } from "jsr:@zod/zod";

const ResponseSchema = z.object({
  meal_name: z.string(),
  protein_g: z.number(),
  not_a_meal: z.boolean().optional(),
});

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization")!;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  try {
    const { description, createdAt } = await req.json();
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const openai = new OpenAI({
      apiKey: apiKey,
    });
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
    } = await supabase.auth.getUser(token);

    const response = await openai.responses.create({
      model: "gpt-5",
      prompt: {
        id: "pmpt_68a51bada3f48194a257c25f203098230279aa2bdc3e9c4d",
      },
      input: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: `${description}`,
            },
          ],
        },
      ],
    });

    // Parse and validate model output
    let parsed: unknown = null;
    try {
      parsed = JSON.parse(response.output_text);
    } catch (_) {
      return new Response(
        JSON.stringify({ error: "Model output was not valid JSON" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
    const parsedResult = ResponseSchema.safeParse(parsed);
    if (!parsedResult.success) {
      return new Response(
        JSON.stringify({
          error: "Model output failed validation",
          issues: parsedResult.error.issues,
        }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }
    const resultData = parsedResult.data;

    if (!resultData.not_a_meal) {
      const { error: insertError } = await supabase.from("meals").insert({
        name: resultData.meal_name,
        protein_amount: resultData.protein_g,
        created_at: createdAt,
        user_id: user.id,
        logging_method: 'manual_entry',
      });

      if (insertError) {
        console.error(insertError);
        return new Response(
          JSON.stringify({ error: "Failed to insert meal" }),
          {
            status: 500,
            headers: { "Content-Type": "application/json" },
          }
        );
      }
    }

    // Update user streak using our simple streak system
    const { data: streakResult, error: streakError } = await supabase
      .rpc('update_user_streak', { target_user_id: user.id });

    if (streakError) {
      console.error('Streak calculation error:', streakError);
      // Don't fail the request if streak calculation fails
    }

    const result = streakResult?.[0] || {
      current_streak: 0,
      streak_extended: false
    };

    console.log('Streak result:', result);

    return new Response(
      JSON.stringify({
        ...resultData,
        currentStreak: result.current_streak,
        streakExtended: result.streak_extended,
        goalMetToday: result.goal_met_today,
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error(error);
    return new Response(
      JSON.stringify({ error: "Failed to analyze meal description" }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
