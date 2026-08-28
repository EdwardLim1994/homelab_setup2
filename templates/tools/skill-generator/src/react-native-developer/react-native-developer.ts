import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { ReactNativeDeveloperGeneratorSchema } from "./schema";

// installs the react-native-developer skills into the workspace `.opencode/skills/` - no project scaffold
export async function reactNativeDeveloperGenerator(
	tree: Tree,
	options: ReactNativeDeveloperGeneratorSchema,
) {
	installSkills(tree, __dirname, "react-native-developer", options);
	await formatFiles(tree);
}

export default reactNativeDeveloperGenerator;
