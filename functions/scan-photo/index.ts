import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js";
import OpenAI from "npm:openai";
import { z } from "npm:zod";
import { zodResponseFormat } from "npm:openai/helpers/zod";

const ResponseSchema = z.object({
  meal_name: z.string(),
  protein_g: z.number(),
  // explanation: z.string().optional(),
});

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization")!;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  const supabaseAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      }
    }
  )

  try {
    const { imagePath, createdAt } = await req.json()
  const apiKey = Deno.env.get('OPENAI_API_KEY')
  const openai = new OpenAI({
    apiKey: apiKey,
  })
  const token = authHeader.replace("Bearer ", "");
    const { data: { user } } = await supabase.auth.getUser(token);

  const { data: { signedUrl }, error: signedUrlError } = await supabase
  .storage
  .from('temp')
  .createSignedUrl(imagePath, 3600)

  if (signedUrlError) {
    console.error(signedUrlError);
    return new Response(JSON.stringify({ error: "Failed to get signed URL" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }


    const response = await openai.beta.chat.completions.parse({
      model: "gpt-4o",
      messages: [
        {
          role: "system",
          content: [
            { type: "text", text: `You are a helpful AI assistant capable of analyzing images to identify meals and estimate their protein content. Please follow these rules:

1. **Meal Identification**: Identify or name the meal as accurately as possible based on the visual features.
2. **Protein Estimation**: Estimate the grams of protein in the meal. Provide a numeric value (for example, 25 grams).

You have access to an image that the user is providing. You are to analyze it strictly under these guidelines.
` },
          ],
        },
        {
          role: "user",
          content: [
            { type: "text", text: `Please analyze the attached image of my meal and respond in JSON with the following fields:
- "meal_name": The name or best guess of the dish.
- "protein_g": The approximate grams of protein in this meal (numeric value).
` },
            {
              type: "image_url",
              image_url: {
                "url": signedUrl,
              },
            },
          ],
        },
      ],
      response_format: zodResponseFormat(ResponseSchema, "response"),
    });

    console.log(response.choices[0].message.parsed);

    const { data, error } = await supabaseAdmin.storage.from("temp").remove([imagePath]);

    if (error) {
      console.error(error);
      return new Response(JSON.stringify({ error: "Failed to remove image" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const {error: insertError} = await supabase.from("meals").insert({
      name: response.choices[0].message.parsed.meal_name,
      protein_amount: response.choices[0].message.parsed.protein_g,
      created_at: createdAt,
      user_id: user.id,
    })

    if (insertError) {
      console.error(insertError);
      return new Response(JSON.stringify({ error: "Failed to insert meal" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

  return new Response(
    JSON.stringify(response.choices[0].message.parsed),
    { headers: { "Content-Type": "application/json" } },
    )

  } catch (error) {
    console.error(error);
    return new Response(JSON.stringify({ error: "Failed to scan photo" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

})
