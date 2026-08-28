import type { NextConfig } from "next";
import { createSecurityHeaders } from "./lib/security-headers.ts";

const nextConfig: NextConfig = {
  async headers() {
    return [
      {
        source: "/:path*",
        headers: createSecurityHeaders(),
      },
    ];
  },
};

export default nextConfig;
