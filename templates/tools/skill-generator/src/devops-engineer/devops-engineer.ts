import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { DevopsEngineerGeneratorSchema } from "./schema";

// installs the devops-engineer skills into the workspace `.opencode/skills/` - no project scaffold
export async function devopsEngineerGenerator(
	tree: Tree,
	options: DevopsEngineerGeneratorSchema,
) {
	installSkills(tree, __dirname, "devops-engineer", options);
}

export default devopsEngineerGenerator;
