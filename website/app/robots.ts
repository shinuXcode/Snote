import type { MetadataRoute } from "next";

const site = "https://snotee.vercel.app";

export default function robots(): MetadataRoute.Robots {
  const crawlable = { userAgent: "*", allow: "/", disallow: ["/api/"] };
  const searchAgents = ["Googlebot", "Bingbot", "OAI-SearchBot", "PerplexityBot"];
  return {
    rules: [
      crawlable,
      ...searchAgents.map(userAgent => ({ userAgent, allow: "/", disallow: ["/api/"] }))
    ],
    sitemap: `${site}/sitemap.xml`,
    host: site
  };
}
