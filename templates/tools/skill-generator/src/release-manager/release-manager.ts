import { formatFiles, type Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { ReleaseManagerGeneratorSchema } from "./schema";

// installs the release-manager skills into the workspace `.opencode/skills/` - no project scaffold
export async function releaseManagerGenerator(
	tree: Tree,
	options: ReleaseManagerGeneratorSchema,
) {
	installSkills(tree, __dirname, "release-manager", options);
	await formatFiles(tree);
}

export default releaseManagerGenerator;
