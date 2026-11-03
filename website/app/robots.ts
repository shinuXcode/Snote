import type { MetadataRoute } from "next";
export default function robots(): MetadataRoute.Robots {
 return { rules: [{ userAgent: "*", allow: "/", disallow: ["/account"] }], sitemap: "https://snotee.vercel.app/sitemap.xml", host: "https://snotee.vercel.app" };
}
