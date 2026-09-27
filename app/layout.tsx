import "./globals.css";
import type { Metadata, Viewport } from "next";
export const metadata: Metadata = { title: "Tranquility Lodge", description: "Tranquility Lodge operations management", manifest: "/manifest.webmanifest" };
export const viewport: Viewport = { width: "device-width", initialScale: 1, viewportFit: "cover", themeColor: "#0f766e" };
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) { return <html lang="en"><body>{children}</body></html>; }

