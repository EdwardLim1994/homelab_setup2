import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { FrontendDeveloperGeneratorSchema } from "./schema";

// installs the frontend-developer skills into the workspace `.opencode/skills/` - no project scaffold
export async function frontendDeveloperGenerator(
	tree: Tree,
	options: FrontendDeveloperGeneratorSchema,
) {
	installSkills(tree, __dirname, "frontend-developer", options);
	await formatFiles(tree);
}

export default frontendDeveloperGenerator;
