import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js";
import OpenAI from "jsr:@openai/openai";
import { z } from "jsr:@zod/zod";
import { TrophyApiClient } from "npm:@trophyso/node";

const trophy = new TrophyApiClient({ apiKey: Deno.env.get("TROPHY_API_KEY")! });

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
    const { imagePath, createdAt } = await req.json();
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    const openai = new OpenAI({
      apiKey: apiKey,
    });
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
    } = await supabase.auth.getUser(token);

    const {
      data: { signedUrl },
      error: signedUrlError,
    } = await supabase.storage.from("temp").createSignedUrl(imagePath, 3600);

    if (signedUrlError) {
      console.error(signedUrlError);
      return new Response(
        JSON.stringify({ error: "Failed to get signed URL" }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

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
              type: "input_image",
              image_url: signedUrl,
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

    const { data, error } = await supabaseAdmin.storage
      .from("temp")
      .remove([imagePath]);

    if (error) {
      console.error(error);
      return new Response(JSON.stringify({ error: "Failed to remove image" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    if (!resultData.not_a_meal) {
      const { error: insertError } = await supabase.from("meals").insert({
        name: resultData.meal_name,
        protein_amount: resultData.protein_g,
        created_at: createdAt,
        user_id: user.id,
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

    const result = await trophy.metrics.event("protein-grams", {
      user: {
        id: user.id,
        email: user.email,
        tz: user.user_metadata.timezone,
      },
      value: resultData.protein_g,
    });

    console.log(result);

    return new Response(
      JSON.stringify({
        ...resultData,
        currentStreak: result.currentStreak.length,
        streakExtended: result.currentStreak.extended,
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: "Failed to scan photo" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
