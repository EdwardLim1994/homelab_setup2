import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { ProjectManagerGeneratorSchema } from "./schema";

// installs the project-manager skills into the workspace `.opencode/skills/` - no project scaffold
export async function projectManagerGenerator(
	tree: Tree,
	options: ProjectManagerGeneratorSchema,
) {
	installSkills(tree, __dirname, "project-manager", options);
}

export default projectManagerGenerator;
