// Not web: no browser online state; the request signal is the only one.
bool isOnline() => true;

void listen(void Function(bool online) onChange) {}
