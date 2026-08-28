import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { QaEngineerGeneratorSchema } from "./schema";

// installs the qa-engineer skills into the workspace `.opencode/skills/` - no project scaffold
export async function qaEngineerGenerator(
	tree: Tree,
	options: QaEngineerGeneratorSchema,
) {
	installSkills(tree, __dirname, "qa-engineer", options);
	await formatFiles(tree);
}

export default qaEngineerGenerator;
