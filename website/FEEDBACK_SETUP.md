# Snote Showcase feedback setup

The website feedback and rating form stores submissions as issues in the public `shinuXcode/Snote` GitHub repository. It does not use browser storage or Supabase.

## Vercel environment variables

In the Vercel project settings for the showcase website, add:

- `SNOTE_FEEDBACK_GITHUB_TOKEN`: a fine-grained GitHub token scoped only to `shinuXcode/Snote`, with **Issues: Read and write** permission. Keep it server-side; never prefix it with `NEXT_PUBLIC_`.
- `SNOTE_FEEDBACK_REPOSITORY`: `shinuXcode/Snote` (optional; this is the default).

Redeploy the website after setting these values. Without the token, the form returns a clear error and does not save feedback anywhere.

## Public visibility

Submitted ratings and comments become public GitHub issues. Any optional contact email is also published in the issue body, so submitters are warned before sending. Do not request passwords, account details, or other sensitive information.

## Notifications

The notification centre reads published GitHub releases through `/api/notifications`; it does not store notification state in the browser. Updates can take up to five minutes to refresh due to server-side caching.
