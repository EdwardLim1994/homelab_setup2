import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { BackendDeveloperGeneratorSchema } from "./schema";

// installs the backend-developer skills into the workspace `.opencode/skills/` - no project scaffold
export async function backendDeveloperGenerator(
	tree: Tree,
	options: BackendDeveloperGeneratorSchema,
) {
	installSkills(tree, __dirname, "backend-developer", options);
	await formatFiles(tree);
}

export default backendDeveloperGenerator;
