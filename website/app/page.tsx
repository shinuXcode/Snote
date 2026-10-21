import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";
export const metadata: Metadata = { title: "Snote — Open-Source Notes for Creators", description: "Snote is an open-source note-taking app for stylus handwriting, digital notebooks, PDF reading and annotation, and local-first workflows. Explore features, docs, and releases.", alternates: { canonical: "https://snote-showcase.vercel.app/" }, openGraph: { title: "Snote — Notes for Creators", description: "Open-source, local-first note-taking for handwriting and ideas.", url: "https://snote-showcase.vercel.app/", type: "website" } };
export default function Home() { return <MotionHero />; }
