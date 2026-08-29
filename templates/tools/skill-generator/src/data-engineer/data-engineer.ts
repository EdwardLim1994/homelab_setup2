import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { DataEngineerGeneratorSchema } from "./schema";

// installs the data-engineer skills into the workspace `.opencode/skills/` - no project scaffold
export async function dataEngineerGenerator(
	tree: Tree,
	options: DataEngineerGeneratorSchema,
) {
	installSkills(tree, __dirname, "data-engineer", options);
}

export default dataEngineerGenerator;
