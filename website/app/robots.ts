import type { MetadataRoute } from "next";
export default function robots(): MetadataRoute.Robots {
 return { rules: [{ userAgent: "*", allow: "/", disallow: ["/account"] }], sitemap: "https://snote-showcase.vercel.app/sitemap.xml", host: "https://snote-showcase.vercel.app" };
}
