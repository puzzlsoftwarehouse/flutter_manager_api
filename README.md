Manager API

Manager API is a Flutter package that simplifies the management of GraphQL and REST API requests. It allows you to make requests with standardized returns, making it easier and more efficient to work with APIs.

## Installation

To install the Manager API, add the following dependency to your `pubspec.yaml`:

```yaml
dependencies:
  manager_api: ^version
```
Replace version with the latest version of Manager API.

## Configuration
To use the Manager API, you need to configure some environment variables:

- BASEAPIURL: The base URL of your API.
- BASETOKENPROJECT: The project token for authentication.
These environment variables should be defined in your .env file.

Usage
After installing and configuring the Manager API, you can use it to make requests to your API. Here is an example of how you can make a GET request:
add files of .graphql on this folder lib/src/services/graphql/

exemplo:
login.graphql
```graphql
mutation login($email: String!, $password: String!) {
    Login(dataLogin: {email: $email, password: $password}) {
        authToken {
            token
            user {
                email
                fullname
                id
                profilePicture
            }
        }
    }
}
```

```dart
import 'package:manager_api/manager_api.dart';

class GraphQLLogin{
  GraphQLLogin._();
  static GraphQLRequest loginWithEmailAndPassword({
    required String email,
    required String password,
  }) =>
      GraphQLRequest<ResultLR<Failure, User>>(
        name: "login",
        path: "login.graphql",
        type: RequestGraphQLType.mutation,
        variables: {
          "email": email,
          "password": password,
        },
        returnRequest: (Map<String, dynamic> data) =>
            User.fromJson(data['Login']['authToken']),
      );
}
```
As seen above, the path would be the file in the services/graphql folder
and name would be the name of the query or mutation
```dart
import 'package:manager_api/manager_api.dart';

void main()async{
 ManagerAPI managerAPI = ManagerAPI();
 ResultLR<Failure,dynamic> result = await manager.request(name:"login",request:GraphQLLogin.loginWithEmailAndPassword(email: "email",password: "password"));
 //your code....
}
```


Contribution
Contributions are welcome! If you find a bug or have a feature suggestion, feel free to open an issue on GitHub.

License
Manager API is licensed under the MIT License.