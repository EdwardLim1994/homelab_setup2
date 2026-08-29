import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { TechnicalWriterGeneratorSchema } from "./schema";

// installs the technical-writer skills into the workspace `.opencode/skills/` - no project scaffold
export async function technicalWriterGenerator(
	tree: Tree,
	options: TechnicalWriterGeneratorSchema,
) {
	installSkills(tree, __dirname, "technical-writer", options);
}

export default technicalWriterGenerator;
