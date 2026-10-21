import type { MetadataRoute } from "next";
const base = "https://snote-showcase.vercel.app";
export default function sitemap(): MetadataRoute.Sitemap {
 const routes = ["/","/features","/how-it-works","/docs","/faqs","/download","/founder","/contact","/privacy","/terms"];
 return routes.map((route) => ({ url: base + route, changeFrequency: route === "/" ? "weekly" : "monthly", priority: route === "/" ? 1 : ["/docs","/faqs","/download"].includes(route) ? 0.8 : ["/privacy","/terms"].includes(route) ? 0.4 : 0.6 }));
}
