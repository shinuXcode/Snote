import type { MetadataRoute } from "next";
const base = "https://snotee.vercel.app";
export default function sitemap(): MetadataRoute.Sitemap {
 const routes = ["/","/features","/how-it-works","/docs","/faqs","/download","/founder"];
 return routes.map((route) => ({ url: base + route, changeFrequency: route === "/" ? "weekly" : "monthly", priority: route === "/" ? 1 : route === "/docs" || route === "/faqs" || route === "/download" ? 0.8 : 0.6 }));
}
