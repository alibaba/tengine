import select, socket
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setblocking(0)
server.bind(('localhost', 65110))
server.listen(5)
inputs = [server]

while inputs:
    outputs = []
    readable, writable, exceptional = select.select(
        inputs, outputs, inputs)
    for s in readable:
        if s is server:
            connection, client_address = s.accept()
            connection.setblocking(0)
            inputs.append(connection)
        else:
            data = s.recv(1024)
            if not data:
                inputs.remove(s)
                s.close()

    for s in exceptional:
        inputs.remove(s)
        s.close()
