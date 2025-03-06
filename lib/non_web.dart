final window = Window();

class Window {
  Location get location => Location();
  History get history => History();
  Worker get worker => Worker("");
  File get file => File();

  JSString jsString = JSString();
}

class History {
  void replaceState(dynamic data, String title, String url) {}
  String? state;
}

class Location {
  String href = "";
}

class Worker {
  final dynamic worker;
  Worker(this.worker);

  void postMessage(dynamic message) {}
}

class File {}

class JSString {}

class JSBoxedDartObject {}

extension JSStringExtension on JSString {
  JSString get toJS {
    return this;
  }
}

extension StringExtension on String {
  JSString get toJS {
    return JSString();
  }
}

extension MapExtesion on Map {
  JSBoxedDartObject get toJSBox {
    return JSBoxedDartObject();
  }
}
