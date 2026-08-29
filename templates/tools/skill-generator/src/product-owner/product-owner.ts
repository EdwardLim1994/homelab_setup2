import type { Tree } from "@nx/devkit";
import { installSkills } from "../shared";
import type { ProductOwnerGeneratorSchema } from "./schema";

// installs the product-owner skills into the workspace `.opencode/skills/` - no project scaffold
export async function productOwnerGenerator(
	tree: Tree,
	options: ProductOwnerGeneratorSchema,
) {
	installSkills(tree, __dirname, "product-owner", options);
}

export default productOwnerGenerator;
