const fs = require("fs")
const yaml = require("js-yaml")


function parse_pr_title(title) {
    let result = title.match(/(\S+)\((\S+)\):\s*(.*)/i)
    if (!result) {
        return
    }
    return {
        type: result[1],
        scope: result[2],
        message: result[3],
    }
}


function parse_pr_description(description) {
    let parsed = {}

    // jira tickets
    parsed.jiras = description.match(/(kag|fti)-\d+/gmi)

    // extract changelog codeblock
    let lines = description.split(/\r?\n/)
    let idx_start = 0, idx_end = 0

    for (let i = 0; i < lines.length; i++) {
        if (lines[i] === "[//]: # (changelog-anchor)") {
            if (idx_start === 0) {
                idx_start = i
            } else {
                idx_end = i
                break
            }
        }
    }

    let yaml_str = lines.slice(idx_start + 2, idx_end - 1).join("\n")
    console.log("[override changelog]: \n" + yaml_str + "\n")
    let doc = yaml.load(yaml_str)

    Object.keys(doc).forEach(key => {
        if (doc[key] !== null) {
            parsed[key] = doc[key]
        }
    })

    return parsed
}


try {
    let title = fs.readFileSync("/tmp/pr-title.txt", "utf8")
    let parsed_pr_title = parse_pr_title(title)
    if (parsed_pr_title) {
        if (parsed_pr_title.type === "feat") {
            parsed_pr_title.type = "feature"
        } else if (parsed_pr_title.type === "fix") {
            parsed_pr_title.type = "bugfix"
        } else if (parsed_pr_title.type === "chore" && parsed_pr_title.scope === "deps") {
            parsed_pr_title.type = "dependency"
            parsed_pr_title.scope = null
        }

        if (parsed_pr_title.scope && parsed_pr_title.scope.startsWith("plugin")) {
            parsed_pr_title.scope = "Plugin"
        }
    }

    let description = fs.readFileSync("/tmp/pr-description.txt", "utf8");
    let parsed_pr_description = parse_pr_description(description)
    console.log("[parsed pr description]: ")
    console.log(parsed_pr_description)
    console.log()

    let property_indexs = {
        message: 1,
        type: 2,
        scope: 3,
        prs: 4,
        jiras: 5,
        issues: 6,
    }

    let changelog = Object.assign({}, parsed_pr_title, parsed_pr_description)
    Object.keys(changelog).forEach((k) => changelog[k] == null && delete changelog[k]);
    let changelog_yaml = yaml.dump(changelog, {
        sortKeys: function (a, b) {
            return property_indexs[a] < property_indexs[b] ? -1 : 1
        }
    })
    changelog_yaml = changelog_yaml === "{}\n" ? "" : changelog_yaml
    console.log("[generate changelog]:")
    console.log(changelog_yaml)
    console.log()

    let pr = fs.readFileSync("/tmp/pr-number.txt", "utf8")
    let filename = "/tmp/" + pr.trim() + ".yaml"
    fs.writeFileSync(filename, changelog_yaml);
    console.log("Successfully write changelog file at", filename)
} catch (err) {
    console.error(err);
    process.exit(1);
}
