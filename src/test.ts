import { createPackage, PackageType } from './package.ts'
import { getWingetExportPackages, isWingetInstalled } from './utils.ts'

const packages = await getWingetExportPackages()
console.log(packages)

const denoPackage = createPackage({
	name: 'deno',
	type: PackageType.winget,
	packageId: 'DenoLand.deno',
})

console.log(denoPackage)

console.log(await denoPackage.isInstalled())
console.log(await denoPackage.check())

console.log(await isWingetInstalled())
