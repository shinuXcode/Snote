export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const MAX_MESSAGE_LENGTH = 2000;
const allowedKinds = new Set(["General feedback", "Bug report", "Feature request", "Accessibility", "Website issue"]);

export async function POST(request: Request) {
  const token = process.env.GITHUB_TOKEN;
  const repository = process.env.GITHUB_REPOSITORY || "shinuXcode/Snote";
  if (!token) return Response.json({ error: "Feedback storage is not configured yet. No feedback was saved." }, { status: 503 });

  let body: unknown;
  try { body = await request.json(); } catch { return Response.json({ error: "Invalid request body." }, { status: 400 }); }
  if (!body || typeof body !== "object") return Response.json({ error: "Invalid feedback." }, { status: 400 });
  const input = body as Record<string, unknown>;
  if (typeof input.website === "string" && input.website.trim()) return Response.json({ ok: true });
  const rating = Number(input.rating);
  const kind = typeof input.kind === "string" && allowedKinds.has(input.kind) ? input.kind : "General feedback";
  const message = typeof input.message === "string" ? input.message.trim() : "";
  const contact = typeof input.contact === "string" ? input.contact.trim().slice(0, 254) : "";
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) return Response.json({ error: "Choose a rating from 1 to 5." }, { status: 400 });
  if (message.length < 8 || message.length > MAX_MESSAGE_LENGTH) return Response.json({ error: "Feedback must be between 8 and 2,000 characters." }, { status: 400 });
  if (contact && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(contact)) return Response.json({ error: "Enter a valid contact email or leave it blank." }, { status: 400 });

  const title = `[Website Feedback] ${rating}/5 — ${kind}`;
  const issueBody = [
    "## Snote website feedback",
    "",
    `- **Rating:** ${rating}/5`,
    `- **Category:** ${kind}`,
    `- **Source:** Snote Showcase website`,
    contact ? `- **Contact requested by submitter:** ${contact}` : "- **Contact:** Not provided",
    "",
    "## Message",
    message,
    "",
    "---",
    "Submitted through the Snote Showcase feedback form."
  ].join("\n");

  try {
    const response = await fetch(`https://api.github.com/repos/${repository}/issues`, {
      method: "POST",
      headers: {
        Accept: "application/vnd.github+json",
        Authorization: `Bearer ${token}`,
        "X-GitHub-Api-Version": "2022-11-28",
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ title, body: issueBody, labels: ["website-feedback"] }),
      cache: "no-store"
    });
    if (!response.ok) {
      const details = await response.json().catch(() => ({}));
      console.error("GitHub feedback submission failed", response.status, details?.message || "");
      return Response.json({ error: "GitHub could not save this feedback. Nothing was stored in the browser; try again later." }, { status: 502 });
    }
    const issue = await response.json();
    return Response.json({ ok: true, issueUrl: issue.html_url }, { status: 201 });
  } catch {
    return Response.json({ error: "GitHub is unreachable. Feedback was not saved; try again later." }, { status: 503 });
  }
}
