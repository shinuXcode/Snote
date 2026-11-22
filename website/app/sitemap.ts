import type { MetadataRoute } from "next";

const base = "https://snotee.vercel.app";
const pages = [
  ["/", 1, "weekly"],
  ["/features", 0.9, "monthly"],
  ["/how-it-works", 0.8, "monthly"],
  ["/docs", 0.8, "monthly"],
  ["/faqs", 0.8, "monthly"],
  ["/download", 0.9, "weekly"],
  ["/founder", 0.5, "yearly"],
  ["/about-snotee", 0.8, "monthly"],
  ["/android-note-taking-app", 0.8, "monthly"],
  ["/handwriting-notes", 0.8, "monthly"],
  ["/pdf-annotation", 0.8, "monthly"],
  ["/open-source-notes-app", 0.7, "monthly"],
  ["/free-note-taking-app", 0.8, "monthly"],
  ["/goodnotes-alternative", 0.7, "monthly"]
] as const;

export default function sitemap(): MetadataRoute.Sitemap {
  return pages.map(([route, priority, changeFrequency]) => ({
    url: base + route,
    changeFrequency,
    priority
  }));
}
