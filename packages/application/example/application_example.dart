import 'package:application/application.dart';

void main() {
  // EntryService 通过 EntryStore 端口注入；实际编排见应用层集成。
  print(EntryNotFoundError().code);
}
