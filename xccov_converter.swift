#!/usr/bin/swift sh

/**
 Original script can be found at:
 https://gist.github.com/csaby02/ab2441715a89865a7e8e29804df23dc6
 */

import Foundation
// import TSCUtility // https://github.com/apple/swift-package-manager.git ~> 0.5.0
//import TSCUtility // apple/swift-tools-support-core

import ArgumentParser // apple/swift-argument-parser

extension String {
    func contains(elementOfArray: [String]) -> Bool {
        for element in elementOfArray {
            if self.contains(element) {
                return true
            }
        }

        return false
    }
}

/*
 The structure of xccov coverage report generated by the command line tool is represented by the following structures:
*/
struct FunctionCoverageReport: Codable {
    let coveredLines: Int
    let executableLines: Int
    let executionCount: Int
    let lineCoverage: Double
    let lineNumber: Int
    let name: String
}

struct FileCoverageReport: Codable {
    let coveredLines: Int
    let executableLines: Int
    let functions: [FunctionCoverageReport]
    let lineCoverage: Double
    let name: String
    let path: String
}

struct TargetCoverageReport: Codable {
    let buildProductPath: String
    let coveredLines: Int
    let executableLines: Int
    let files: [FileCoverageReport]
    let lineCoverage: Double
    let name: String
}

struct CoverageReport: Codable {
    let executableLines: Int
    let targets: [TargetCoverageReport]
    let lineCoverage: Double
    let coveredLines: Int
}

func generateCoberturaReport(from coverageReport: CoverageReport, targetsToInclude: [String], packagesToExclude: [String], workingDirectory: String, covPath: String) -> String {

    let dtd = try! XMLDTD(contentsOf: URL(string: "http://cobertura.sourceforge.net/xml/coverage-04.dtd")!)
    dtd.name = "coverage"
    dtd.systemID = "http://cobertura.sourceforge.net/xml/coverage-04.dtd"

    let rootElement = XMLElement(name: "coverage")
    rootElement.addAttribute(XMLNode.attribute(withName: "line-rate", stringValue: "\(coverageReport.lineCoverage)") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "branch-rate", stringValue: "1.0") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "lines-covered", stringValue: "\(coverageReport.coveredLines)") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "lines-valid", stringValue: "\(coverageReport.executableLines)") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "timestamp", stringValue: "\(Date().timeIntervalSince1970)") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "version", stringValue: "diff_coverage 0.1") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "complexity", stringValue: "0.0") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "branches-valid", stringValue: "1.0") as! XMLNode)
    rootElement.addAttribute(XMLNode.attribute(withName: "branches-covered", stringValue: "1.0") as! XMLNode)

    let doc = XMLDocument(rootElement: rootElement)
    doc.version = "1.0"
    doc.dtd = dtd
    doc.documentContentKind = .xml

    let sourceElement = XMLElement(name: "sources")
    rootElement.addChild(sourceElement)
    sourceElement.addChild(XMLElement(name: "source", stringValue: workingDirectory))

    let packagesElement = XMLElement(name: "packages")
    rootElement.addChild(packagesElement)

    var allFiles = [FileCoverageReport]()
    for targetCoverageReport in coverageReport.targets {

        guard targetsToInclude.isEmpty || targetsToInclude.contains(targetCoverageReport.name) else {
            continue
        }

        // Filter out files by package
        let targetFiles = targetCoverageReport.files.filter { !$0.path.contains(elementOfArray: packagesToExclude) }
        allFiles.append(contentsOf: targetFiles)
    }

    // Sort files to avoid duplicated packages
    allFiles = allFiles.sorted(by: { $0.path > $1.path })

    var currentPackage = ""
    var currentPackageElement: XMLElement!
    var isNewPackage = false

    for fileCoverageReport in allFiles {
        // Define file path relative to source!
        let filePath = fileCoverageReport.path.replacingOccurrences(of: workingDirectory + "/", with: "")
        let pathComponents = filePath.split(separator: "/")
        let packageName = pathComponents[0..<pathComponents.count - 1].joined(separator: ".")

        isNewPackage = currentPackage != packageName

        if isNewPackage {
            currentPackageElement = XMLElement(name: "package")
            packagesElement.addChild(currentPackageElement)
        }

        currentPackage = packageName
        if isNewPackage {
            currentPackageElement.addAttribute(XMLNode.attribute(withName: "name", stringValue: packageName) as! XMLNode)
            currentPackageElement.addAttribute(XMLNode.attribute(withName: "line-rate", stringValue: "\(fileCoverageReport.lineCoverage)") as! XMLNode)
            currentPackageElement.addAttribute(XMLNode.attribute(withName: "branch-rate", stringValue: "1.0") as! XMLNode)
            currentPackageElement.addAttribute(XMLNode.attribute(withName: "complexity", stringValue: "0.0") as! XMLNode)
        }

        let classElement = XMLElement(name: "class")
        classElement.addAttribute(XMLNode.attribute(withName: "name", stringValue: "\(packageName).\((fileCoverageReport.name as NSString).deletingPathExtension)") as! XMLNode)
        classElement.addAttribute(XMLNode.attribute(withName: "filename", stringValue: "\(filePath)") as! XMLNode)
        classElement.addAttribute(XMLNode.attribute(withName: "line-rate", stringValue: "\(fileCoverageReport.lineCoverage)") as! XMLNode)
        classElement.addAttribute(XMLNode.attribute(withName: "branch-rate", stringValue: "1.0") as! XMLNode)
        classElement.addAttribute(XMLNode.attribute(withName: "complexity", stringValue: "0.0") as! XMLNode)
        currentPackageElement.addChild(classElement)

        let linesElement = XMLElement(name: "lines")
        classElement.addChild(linesElement)

    /* Old Style
        for functionCoverageReport in fileCoverageReport.functions {
            for index in 0..<functionCoverageReport.executableLines {

                // Function coverage report won't be 100% reliable without parsing it by file (would need to use xccov view --file filePath workingDirectory + Build/Logs/Test/ *.xccovarchive)
                let lineElement = XMLElement(kind: .element, options: .nodeCompactEmptyElement)
                lineElement.name = "line"
                lineElement.addAttribute(XMLNode.attribute(withName: "number", stringValue: "\(functionCoverageReport.lineNumber + index)") as! XMLNode)
                lineElement.addAttribute(XMLNode.attribute(withName: "branch", stringValue: "false") as! XMLNode)

                let lineHits: Int
                if index < functionCoverageReport.coveredLines {
                    lineHits = functionCoverageReport.executionCount
                } else {
                    lineHits = 0
                }

                lineElement.addAttribute(XMLNode.attribute(withName: "hits", stringValue: "\(lineHits)") as! XMLNode)
                linesElement.addChild(lineElement)
            }
        } */

        /* Ci sono degli errori nei dati di input: executableLines è sbagliato; da il numero di linee coperte, ma non dice quali, ecc.*/
        /* Consideara le classi coincidenti con i file per cui parso l'intero file */

        let covFile = fileCoverageReport.name + ".cov"
        let slashPath = covPath.hasSuffix("/") ? covPath : covPath + "/"
        guard let covData = try? String(contentsOfFile: (slashPath + covFile)) else {
            return "COV!! \(slashPath + covFile)"
        }
        let covLines = covData.components(separatedBy: .newlines)
        linesElement.addAttribute(XMLNode.attribute(withName: "fileName", stringValue: "\(covFile)") as! XMLNode)

        for index in 0..<covLines.count - 1 {
            guard let lineHits = getLineHits(id: index, lines: covLines) else {
                continue
            }

            let lineElement = XMLElement(kind: .element, options: .nodeCompactEmptyElement)
            lineElement.name = "line"
            lineElement.addAttribute(XMLNode.attribute(withName: "number", stringValue: "\(index)") as! XMLNode)
            lineElement.addAttribute(XMLNode.attribute(withName: "branch", stringValue: "false") as! XMLNode)
            lineElement.addAttribute(XMLNode.attribute(withName: "hits", stringValue: "\(lineHits)") as! XMLNode)

            linesElement.addChild(lineElement)
        }
    }

    return doc.xmlString(options: [.nodePrettyPrint])
}

func getLineHits(id: Int, lines: [String]) -> Int? {

    var subrange = false
    var subHits = 0
    // velocizzo il processo
    let subLines = id > 0 ? Array(lines.dropFirst(id - 1)) : lines

    for line in subLines {

        if subrange == true {
            if line.hasSuffix("]") {
                subrange = false
                return subHits
            }
            var subLine = line.trimmingCharacters(in: .whitespaces)
            subLine.removeFirst()
            subLine.removeLast()
            let components = subLine.components(separatedBy: " ")
            if components.count == 3 {
                var middle = components[1]
                middle.removeLast()     // ","
                var column = components[0]
                column.removeLast()     // ","
                //if Int(middle) != 0 && Int(column) != 1 {
                    subHits = Int(components.last ?? "") ?? 0
                //}
            }
            if subHits == 0 {
                return 0
            }
            continue
        }

        if line.trimmingCharacters(in: .whitespaces).starts(with: "\(id): ") {
            if line.hasSuffix("*") { return nil }
            if line.hasSuffix("[") {
                var startLine = line
                startLine.removeLast()
                startLine = startLine.trimmingCharacters(in: .whitespaces)
                let components = startLine.components(separatedBy: " ")
                subHits = Int(components.last ?? "") ?? 0
                subrange = true
                continue
            }

            let components = line.components(separatedBy: " ")
            let covHits = Int(components.last ?? "") ?? 0
            return covHits
        }
    }
    return nil
}

/*let arguments = Array(ProcessInfo.processInfo.arguments.dropFirst())
let parser = ArgumentParser(usage: "<options>", overview: "Converts xccov reports to Cobertura XML")

let jsonReportPathArg = parser.add(option: "--input", shortName: "-i", kind: String.self, usage: "Path to the JSON xccov report")
let workingDirectoryArg = parser.add(option: "--working-directory", shortName: "-d", kind: String.self, usage: "The current working directory")
let targetsToIncludeArg = parser.add(option: "--targetsToInclude", shortName: "-t", kind: [String].self, usage: "List of targets to include in the coverage report")
let packagesToExcludeArg = parser.add(option: "--packagesToExclude", shortName: "-p", kind: [String].self, usage: "List of packages to exclude from the coverage report")

let covPathArg = parser.add(option: "--linesCoverage", shortName: "-c", kind: String.self, usage: "Path of detailed coverage files")     // "linescov/"

let parsedArguments = try parser.parse(arguments) */

struct Coverter: ParsableCommand {

    @Option(name: [.customShort("i"), .customLong("input")], help: "Path to the JSON xccov report")
    var jsonReportPath: String

    @Option(name: [.customShort("d"), .long], help: "The current working directory.")
    var workingDirectoryArg: String

    //@Flag(name: .shortAndLong, help: "Print status updates while counting.")
    //var verbose: Bool

    @Option(name: [.short, .customLong("targetsToInclude")], help: "List of targets to include in the coverage report.")
    var targetsToIncludeArg: [String]

    @Option(name: [.short, .customLong("packagesToExclude")], help: "List of packages to exclude from the coverage report")
    var packagesToExcludeArg: [String]

    @Option(name: [.customShort("c"), .customLong("linesCoverage")], help: "Path of detailed coverage files.")
    var covPath: String

    func run() throws {
    	let workingDirectory = workingDirectoryArg ?? FileManager.default.currentDirectoryPath

	// Trying to get the JSON String from the input parameter filePath
	    guard let json = try? String(contentsOfFile: jsonReportPath, encoding: .utf8), let data = json.data(using: .utf8) else {
   	    print("Cannot read content of \(jsonReportPath)")
            return
	}

        // Trying to decode the JSON into CoverageReport structure
        guard let report = try? JSONDecoder().decode(CoverageReport.self, from: data) else {
            print("Invalid input format")
            return
        }

        let targetsToInclude = targetsToIncludeArg ?? []
        let packagesToExclude = packagesToExcludeArg ?? []
        let coberturaReport = generateCoberturaReport(from: report,
	        				      targetsToInclude: targetsToInclude,
	        				      packagesToExclude: packagesToExclude,
			        		      workingDirectory: workingDirectory,
		        			      covPath: covPath)
        print("\(coberturaReport)")
    }
}

Coverter.main()
