import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";

const siteUrl = "https://snote-showcase.vercel.app";
export const metadata: Metadata = {
 title: { absolute: "Snote — Open-Source Handwriting Notes & PDF Annotation" },
 description: "Snote is an open-source, local-first note-taking workspace for stylus handwriting, digital notebooks, rich text, PDF reading and annotation. Explore features, documentation, releases, and source code.",
 alternates: { canonical: siteUrl + "/" },
 keywords: ["Snote","Snote note taking app","open-source note-taking app","handwriting notes app","stylus note-taking","PDF reader and annotation","digital notebook","offline notes","local-first note-taking","Flutter notes app"],
 openGraph: {
  title: "Snote — Open-Source Handwriting Notes & PDF Annotation",
  description: "Explore Snote, an open-source note-taking workspace for handwriting, digital notebooks, and PDF workflows.",
  url: siteUrl + "/", siteName: "Snote", type: "website", locale: "en_US",
  images: [{ url: "/opengraph-image", width: 1200, height: 630, alt: "Snote — open-source handwriting notes and PDF annotation" }]
 },
 twitter: {
  card: "summary_large_image",
  title: "Snote — Open-Source Handwriting Notes & PDF Annotation",
  description: "Open-source, local-first notes for handwriting, digital notebooks, and PDF workflows.",
  images: ["/opengraph-image"]
 }
};
export default function Home() { return <MotionHero />; }
