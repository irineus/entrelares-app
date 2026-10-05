String? _note;

/// Native half: in memory — the hosted checkout is a web-rail affair.
String? readCheckoutNote() => _note;

void writeCheckoutNote(String value) => _note = value;

void clearCheckoutNote() => _note = null;
