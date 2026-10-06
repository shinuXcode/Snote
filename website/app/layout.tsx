import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Snote — Open-source notes",
  description: "Offline-first handwriting and rich-text notes.",
};

export default function RootLayout({children}: {children: React.ReactNode}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
