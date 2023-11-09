class StringConverter {
  StringConverter._();

  static snakeCaseToCamelCase(String snakeCase) {
    String camelCase = snakeCase.replaceAllMapped(
        RegExp(r'([a-zA-Z])'), (match) => match.group(1)!.toUpperCase());
    return camelCase[0].toUpperCase() + camelCase.substring(1);
  }

  static camelCaseToSnakeCase(String camelCase) {
    String snakeCase = camelCase.replaceAllMapped(
        RegExp(r'(?<!^)[A-Z]'), (match) => '_${match.group(0)!.toLowerCase()}');
    return snakeCase.toLowerCase();
  }
}
