import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const authHeader = req.headers.get("Authorization")!;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    { global: { headers: { Authorization: authHeader } } }
  );

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { autoRefreshToken: false, persistSession: false } }
  );

  try {
    const token = authHeader.replace("Bearer ", "");
    const { data } = await supabase.auth.getUser(token);
    const user_id = data.user?.id;
    console.log("user_id", user_id);

    if (!user_id) {
      return new Response(
        JSON.stringify({ success: false, error: "User ID is required" }),
        {
          status: 400,
          headers: { "Content-Type": "application/json" },
        }
      );
    }

    const { error } = await supabaseAdmin.auth.admin.deleteUser(user_id);

    if (error) throw error;
    return new Response(
      JSON.stringify({ success: true, message: "User deleted successfully" }),
      {
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error deleting account:", error);
    return new Response(JSON.stringify({ success: false, error: error }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
