import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { ReactDeveloperGeneratorSchema } from "./schema";

// installs the react-developer skills into the workspace `.opencode/skills/` - no project scaffold
export async function reactDeveloperGenerator(
	tree: Tree,
	options: ReactDeveloperGeneratorSchema,
) {
	installSkills(tree, __dirname, "react-developer", options);
	await formatFiles(tree);
}

export default reactDeveloperGenerator;
