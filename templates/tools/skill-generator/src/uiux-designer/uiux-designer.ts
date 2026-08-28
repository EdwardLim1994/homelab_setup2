import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { UiuxDesignerGeneratorSchema } from "./schema";

// installs the uiux-designer skills into the workspace `.opencode/skills/` - no project scaffold
export async function uiuxDesignerGenerator(
	tree: Tree,
	options: UiuxDesignerGeneratorSchema,
) {
	installSkills(tree, __dirname, "uiux-designer", options);
	await formatFiles(tree);
}

export default uiuxDesignerGenerator;
