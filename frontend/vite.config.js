import { defineConfig } from 'vite'

export default defineConfig({
  base: './',
  assetsInclude: [],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main:   'index.html',
        manual: 'src/manual_fluent.html',
      },
      output: {
        entryFileNames: 'assets/[name].js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name].[ext]',
      }
    }
  },
  server: {
    port: 5173,
    strictPort: true,
  }
})
