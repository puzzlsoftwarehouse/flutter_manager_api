import 'package:flutter_test/flutter_test.dart';
import 'package:manager_api/requests/graphql_request.dart';

void main() {
  loadQuery(
    RequestGraphQLType type,
    String requestName,
    String fileResult,
  ) async {
    String lineIncrement = "";
    String result = "";

    int quantityOpen = 0;
    int quantityClose = 0;
    String stringType = type == RequestGraphQLType.query ? "query" : "mutation";
    bool firstLine = false;
    List<String> fragments = [];

    for (String line in fileResult.split("\n")) {
      if (result.isNotEmpty) break;

      RegExp regex = RegExp("$stringType $requestName\\s*" r'(?=[({])');
      if (regex.hasMatch(line)) {
        firstLine = true;
      }
      if (firstLine) {
        quantityOpen += line.split("{").length;
        quantityClose += line.split("}").length;
        if (quantityOpen == quantityClose) {
          lineIncrement += line;
          result = lineIncrement;
          break;
        }
        lineIncrement += line;

        // Check for fragment usage
        RegExp fragmentUsageRegex = RegExp(r'\.\.\.\s*(\w+)');
        Iterable<RegExpMatch> matches = fragmentUsageRegex.allMatches(line);
        for (var match in matches) {
          if (match.group(1) != null) {
            fragments.add(match.group(1)!);
          }
        }
      }
    }

    // Append fragments to the result
    for (String fragment in fragments) {
      RegExp fragmentRegex =
          RegExp(r'fragment\s+' + fragment + r'\s+on\s+\w+\s*\{[^}]*\}');
      Iterable<RegExpMatch> fragmentMatches =
          fragmentRegex.allMatches(fileResult);
      for (var match in fragmentMatches) {
        result += "\n" + match.group(0)!;
      }
    }

    return result.trim();
  }

  test("teste", () {
    String query = """
    
fragment Task on gTask{
    id
    parentTaskId
    thumbnail {
        id
        data {
            blurHash
            datum
        }
        creator {
            id
            fullname
            profilePicture
        }
        dateCreated
    }
    milestoneItem {
        id
        milestone {
            id
            name
            deliverable {
                id
                name
            }
        }
    }
    name
    team {
        id
        fullname
    }
    status {
        id
        name
        slug
        groupColor {
            id
            colors {
                hexadecimalNumber
                colorType {
                    slug
                }
            }
        }

    }
    priority {
        id
        name
        slug
        groupColor {
            id
            colors {
                hexadecimalNumber
                colorType {
                    slug
                }
            }
        }
    }
    thumbnail {
        id
        data {
            blurHash
            datum
        }
        creator {
            id
            fullname
            profilePicture
        }
        dateCreated
    }
    startDate
    endDate
    estimatedDays
    teamTimeSpent
}

query getTasksPage(\$milestoneItemId:Int,\$perPage:Int,\$page:Int,\$parentTaskId:Int){
    Task{
        all(milestoneItemId:\$milestoneItemId,perPage: \$perPage,page: \$page,parentTaskId: \$parentTaskId){
            items {
                ... Task
                subtasks(perPage: \$perPage){
                    totalCount
                    items {
                        ... Task
                        subtasks {
                            totalCount
                        }
                    }
                }
            }
        }
    }
}
""";
    expect(loadQuery(RequestGraphQLType.query, "getTasksPage", query), "");
  });
}
