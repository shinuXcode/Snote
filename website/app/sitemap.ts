import type { MetadataRoute } from "next";
const base = "https://snote-showcase.vercel.app";
export default function sitemap(): MetadataRoute.Sitemap {
 const routes = ["/","/features","/how-it-works","/docs","/faqs","/download","/founder","/contact","/privacy","/terms"];
 return routes.map((route) => ({ url: base + route, lastModified: new Date("2026-10-21T00:00:00.000Z"), changeFrequency: route === "/" ? "weekly" : "monthly", priority: route === "/" ? 1 : route === "/docs" || route === "/faqs" || route === "/download" ? 0.8 : 0.6 }));
}
