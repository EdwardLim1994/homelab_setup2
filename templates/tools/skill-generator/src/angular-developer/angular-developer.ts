import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { AngularDeveloperGeneratorSchema } from "./schema";

// installs the angular-developer skills into the workspace `.opencode/skills/` - no project scaffold
export async function angularDeveloperGenerator(
	tree: Tree,
	options: AngularDeveloperGeneratorSchema,
) {
	installSkills(tree, __dirname, "angular-developer", options);
}

export default angularDeveloperGenerator;
