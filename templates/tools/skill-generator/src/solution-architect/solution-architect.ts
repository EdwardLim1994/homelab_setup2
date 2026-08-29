import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { SolutionArchitectGeneratorSchema } from "./schema";

// installs the solution-architect skills into the workspace `.opencode/skills/` - no project scaffold
export async function solutionArchitectGenerator(
	tree: Tree,
	options: SolutionArchitectGeneratorSchema,
) {
	installSkills(tree, __dirname, "solution-architect", options);
}

export default solutionArchitectGenerator;
