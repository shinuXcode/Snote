import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";
export const metadata: Metadata = { title: "Snotee — Open-Source Notes for Creators", description: "Write by hand, organize ideas, and work with rich text and documents in Snotee, an open-source, local-first note-taking workspace.", alternates: { canonical: "https://snotee.vercel.app/" }, openGraph: { title: "Snotee — Notes for Creators", description: "Open-source, local-first note-taking for handwriting and ideas.", url: "https://snotee.vercel.app/", type: "website" } };
export default function Home() { return <MotionHero />; }
