import { defineConfig } from "vite";
import { nodePolyfills } from "vite-plugin-node-polyfills";

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [nodePolyfills()],
  build: {
    cssCodeSplit: true,
    chunkSizeWarningLimit: 2000,
  },
});
