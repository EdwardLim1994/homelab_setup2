import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { TechLeadGeneratorSchema } from "./schema";

// installs the tech-lead skills into the workspace `.opencode/skills/` - no project scaffold
export async function techLeadGenerator(
	tree: Tree,
	options: TechLeadGeneratorSchema,
) {
	installSkills(tree, __dirname, "tech-lead", options);
	await formatFiles(tree);
}

export default techLeadGenerator;
