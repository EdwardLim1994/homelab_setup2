import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { SecurityEngineerGeneratorSchema } from "./schema";

// installs the security-engineer skills into the workspace `.opencode/skills/` - no project scaffold
export async function securityEngineerGenerator(
	tree: Tree,
	options: SecurityEngineerGeneratorSchema,
) {
	installSkills(tree, __dirname, "security-engineer", options);
	await formatFiles(tree);
}

export default securityEngineerGenerator;
