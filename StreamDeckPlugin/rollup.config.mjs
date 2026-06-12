import resolve from "@rollup/plugin-node-resolve";
import typescript from "@rollup/plugin-typescript";

export default {
  input: "src/plugin.ts",
  output: {
    file: "com.danbasnett.jiratimetracker.sdPlugin/bin/plugin.js",
    format: "es",
    sourcemap: false,
  },
  plugins: [
    resolve(),
    typescript(),
  ],
};
