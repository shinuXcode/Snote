import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";
export const metadata: Metadata = { title: "Snote — Open-Source Notes for Creators", description: "Write by hand, organize ideas, and work with rich text and documents in Snote, an open-source, local-first note-taking workspace.", alternates: { canonical: "https://snote-showcase.vercel.app/" }, openGraph: { title: "Snote — Notes for Creators", description: "Open-source, local-first note-taking for handwriting and ideas.", url: "https://snote-showcase.vercel.app/", type: "website" } };
export default function Home() { return <MotionHero />; }
