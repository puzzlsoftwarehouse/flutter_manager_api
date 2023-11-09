extension StringConvert on String {
  String snakeCaseToCamelCase() {
    String camelCase = replaceAllMapped(
        RegExp(r'([a-zA-Z])'), (match) => match.group(1)!.toUpperCase());
    return camelCase[0].toUpperCase() + camelCase.substring(1);
  }

  String camelCaseToSnakeCase() {
    String snakeCase = replaceAllMapped(
        RegExp(r'(?<!^)[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
    return snakeCase.toLowerCase();
  }
}
