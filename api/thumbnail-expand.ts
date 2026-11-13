const FAL_OUTPAINT_URL = "https://fal.run/fal-ai/image-apps-v2/outpaint";
const SUPABASE_URL = "https://akdvrpqgwsopplsibefn.supabase.co";
const SUPABASE_PUBLISHABLE_KEY = "sb_publishable_jMKeDhWfdQinR4lFY4T5Mg_Nn7sG9ma";

export const config = {
  maxDuration: 120,
  api: { bodyParser: { sizeLimit: "4mb" } },
};

export default async function handler(req: any, res: any) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Use POST to expand an image." });
  }

  const authorization = req.headers.authorization;
  if (typeof authorization !== "string" || !authorization.startsWith("Bearer ")) {
    return res.status(401).json({ error: "Sign in to your SYNTRIX account before generating an AI expansion." });
  }
  try {
    const identity = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: SUPABASE_PUBLISHABLE_KEY, Authorization: authorization },
    });
    if (!identity.ok) {
      return res.status(401).json({ error: "Your SYNTRIX session has expired. Sign in again and retry." });
    }
  } catch {
    return res.status(503).json({ error: "Could not verify your SYNTRIX session. Please retry shortly." });
  }

  const falKey = process.env.FAL_KEY;
  if (!falKey) {
    return res.status(503).json({
      error: "AI expansion needs a fal.ai API key. Add FAL_KEY to this Vercel project’s Production environment and redeploy.",
    });
  }

  const { image, prompt = "", expand_left, expand_right, expand_top, expand_bottom } = req.body ?? {};
  if (typeof image !== "string" || !/^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$/.test(image)) {
    return res.status(400).json({ error: "Upload a valid JPG, PNG or WebP image." });
  }
  const imageBytes = Math.floor((image.split(",")[1].length * 3) / 4);
  if (imageBytes > 2_800_000) {
    return res.status(413).json({ error: "This image is too large to send. Choose a smaller image and try again." });
  }

  const margins = { expand_left, expand_right, expand_top, expand_bottom };
  for (const [edge, amount] of Object.entries(margins)) {
    if (!Number.isInteger(amount) || (amount as number) < 0 || (amount as number) > 700) {
      return res.status(400).json({ error: `Invalid ${edge} expansion amount.` });
    }
  }
  if (typeof prompt !== "string" || prompt.length > 300) {
    return res.status(400).json({ error: "Scene guidance must be 300 characters or fewer." });
  }

  try {
    const generation = await fetch(FAL_OUTPAINT_URL, {
      method: "POST",
      headers: { Authorization: `Key ${falKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        image_url: image,
        ...margins,
        prompt,
        num_images: 1,
        enable_safety_checker: true,
        output_format: "png",
        sync_mode: true,
      }),
    });

    if (!generation.ok) {
      return res.status(502).json({ error: "The image generation service could not complete this request. Check the fal.ai account and try again." });
    }
    const result = await generation.json();
    const imageUrl = result?.images?.[0]?.url;
    if (typeof imageUrl !== "string") {
      return res.status(502).json({ error: "The image generation service returned no usable image." });
    }
    const parsedImageUrl = new URL(imageUrl);
    if (parsedImageUrl.protocol !== "https:" || !(parsedImageUrl.hostname === "fal.media" || parsedImageUrl.hostname.endsWith(".fal.media"))) {
      return res.status(502).json({ error: "The image generation service returned an invalid download location." });
    }

    const output = await fetch(parsedImageUrl);
    const contentType = output.headers.get("content-type") ?? "";
    if (!output.ok || !contentType.startsWith("image/")) {
      return res.status(502).json({ error: "The generated image could not be downloaded. Please try again." });
    }
    const bytes = new Uint8Array(await output.arrayBuffer());
    if (bytes.length > 20_000_000) {
      return res.status(502).json({ error: "The generated image exceeded the download limit." });
    }

    res.setHeader("Content-Type", contentType);
    res.setHeader("Content-Length", String(bytes.length));
    res.setHeader("Cache-Control", "no-store");
    return res.status(200).send(Buffer.from(bytes));
  } catch {
    return res.status(502).json({ error: "Could not reach the image generation service. Please try again." });
  }
}
