import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const respond = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  if (req.method !== "POST") return respond({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    const { videoId, youtubeAccessToken } = await req.json();
    if (!jwt || !videoId || !youtubeAccessToken) return respond({ error: "Missing sign-in or upload details." }, 400);

    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceKey) return respond({ error: "SYNTRIX publishing verification is not configured yet." }, 503);

    const authClient = createClient(url, anonKey, { auth: { persistSession: false } });
    const { data: userData, error: authError } = await authClient.auth.getUser(jwt);
    if (authError || !userData.user) return respond({ error: "Please sign in again to verify this upload." }, 401);

    // Verify that this video is visible to the same Google account that authorized publishing.
    const check = await fetch("https://www.googleapis.com/youtube/v3/videos?part=snippet,status&id=" + encodeURIComponent(videoId), {
      headers: { Authorization: "Bearer " + youtubeAccessToken },
    });
    if (!check.ok) return respond({ error: "YouTube could not verify this upload. Reconnect your channel and try again." }, 400);
    const payload = await check.json();
    const video = payload.items?.[0];
    if (!video || video.id !== videoId || !video.snippet?.channelId || !["uploaded", "processed"].includes(video.status?.uploadStatus)) {
      return respond({ error: "This video could not be verified as a completed upload on the connected channel." }, 400);
    }

    const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
    const { data, error } = await admin.rpc("record_verified_youtube_upload", {
      p_user_id: userData.user.id,
      p_video_id: videoId,
    });
    if (error) return respond({ error: "The upload is verified, but the SYNTRIX reward record needs setup." }, 503);
    return respond(data);
  } catch (_error) {
    return respond({ error: "Could not verify this YouTube upload. Please try again." }, 500);
  }
});
