class Server:
    # initialiser of the auction server
    # param base is the initial base price for the merchandise to sell
    # param m is the number of clients, i.e. bidders
    # param n is the number of possible values for each bid
    def __init__(self, base, m, n, verbose = False):
        self.init_base = base
        self.curr_base = base
        self.m = m
        self.n = n
        self.verbose = verbose
        self.gen_sys(n)
        self.gen_clients()

    # generate system parameters for diffie-hellman OT
    # param n is the number of h_bar_array
    def gen_sys(self, n):
        self.p = random_prime(2**129-1, false, 2**128)
        self.ZZp = Zmod(self.p)
        self.g = primitive_root(self.p)
        self.g = self.ZZp(self.g)
        self.h_bar_array = []
        for i in range(n-1):
            h_bar = self.ZZp.random_element()
            # h_bars have to be unique
            while h_bar in self.h_bar_array:
                h_bar = self.ZZp.random_element()
            self.h_bar_array.append(h_bar)
        print "System is initialised."
        print
        if self.verbose:
            print "Prime modulus p =", self.p
            print "Generator g =", self.g
            print "Public h_bars are:", self.h_bar_array

    # generate a client, and
    # pass system parameters to the client
    def gen_client(self, client_index):
        client = Client(client_index, self.p, self.g, self.n, self.h_bar_array, self.verbose)
        self.clients.append(client)

    # generate all clients
    def gen_clients(self):
        self.clients = []
        for i in range(self.m):
            self.gen_client(i)
        print

    # compare bid price of two clients
    # param one and another are indices of the clients
    # return the index of the client who wins the comparison
    def compare_bid(self, one, another):
        r_eq = self.ZZp.random_element() # random value for 'equal' flag
        r_lt = self.ZZp.random_element() # ramdom value for 'less than' flag
        while r_lt == r_eq:
            r_lt = self.ZZp.random_element()
        r_gt = self.ZZp.random_element() # ramdom value for 'greater than' flag
        while r_gt == r_eq or r_gt == r_lt:
            r_gt = self.ZZp.random_element()

        receiver = self.clients[one]
        sender = self.clients[another]
        # step 1: the 'Receiver' send its public h values to the Server
        h_array = receiver.get_h_array()
        # step 2: the 'Sender' form a flag array and encrypt the array using the 'Receiver''s public h values
        encrypted = sender.encrypt_flag_array(r_lt, r_eq, r_gt, h_array)
        # step 3: the 'Receiver' decrypts (As, Bs) pair by computing Bs / As^us
        #         and send it back to the Server
        decrypted = receiver.decrypt_flag(encrypted)

        if decrypted == self.g ** r_lt: # one < another
            return another
        elif decrypted == self.g ** r_gt: # one > another
            return one
        elif decrypted == self.g ** r_eq: # one == another
            # in real scenarios, bid information could be sent over tcp connections
            # thus, we can resolve the situation when two bid prices are equal
            # by looking at their timestamps when the packet is arrived at the server
            # which means we prefer the earlier one
            # but in this PoC code, we just simply return the first one
            return one
        else:
            # error! could be a cheating client!
            return

    # find the index of the client who made a highest bid
    def find_round_winner(self):
        winner = 0
        for i in range(1,self.m):
            winner = self.compare_bid(winner, i)
        return winner

    # reveal the secret bid price of a client
    # in this scenario the server itself acts as a 'Sender'
    # used at the end of each round of the auction
    # or when some client is found cheating
    def reveal_secret(self, client_index):
        # generate n unique random values
        r_array = []
        power_r_array = []
        for i in range(self.n):
            r_i = self.ZZp.random_element()
            while r_i in r_array:
                r_i = self.ZZp.random_element()
            r_array.append(r_i)
            power_r_array.append(self.g**r_i)

        # encrypt the array using the client's public h values
        receiver = self.clients[client_index]
        h_array = receiver.get_h_array()
        encrypted = []
        for i in range(self.n):
            r = self.ZZp.random_element()
            A = self.g ** r
            B = (h_array[i] ** r) * (self.g ** r_array[i])
            encrypted.append((A,B))

        # ask the client to decrypt the only value it is able to
        # which has an index equals its secret
        # by finding the index of decrypted value in the power_r_array
        # the secret of client is revealed
        if self.verbose:
            print "Power r array:", power_r_array
        decrypted = receiver.decrypt_flag(encrypted)
        # secret = power_r_array.index(decrypted) not working
        for i in range(self.n):
            if power_r_array[i] == decrypted:
                secret = i
                break
        return secret

    # main function for auctions
    def begin_auction(self):
        print "The auction is beginning..."
        rnd = 0
        finished = False
        while not finished:
            print "This is round", rnd
            print "The current base price is", self.curr_base
            print "Every client please make a bid"
            print "The bid price should be from 0 to", self.n - 1
            print "Zero bid price for giving up in this round"
            print
            for client in self.clients:
                client.bid()
            winner = self.find_round_winner()
            highest_bid = self.reveal_secret(winner)
            print
            if highest_bid == 0:
                finished = True
                print "The auction is finished..."
                if rnd == 0:
                    print "Sadly, the merchandise is not sold"
                else:
                    print "The winner is Client", fin_winner
                    print "The final price is", self.curr_base
            else:
                print "The winner in this round is Client", winner
                fin_winner = winner
                print "The highest bid price in this round is", highest_bid
                print "This price will be added to the base, let us begin next round"
                self.curr_base += highest_bid
                rnd += 1
                print

class Client:
    def __init__(self,client_index, p, g, n, h_bar_array, verbose = False):
        self.client_index = client_index
        self.p = p
        self.ZZp = Zmod(self.p)
        self.g = g
        self.n = n
        self.h_bar_array = h_bar_array
        self.verbose = verbose
        print "Client", self.client_index, "is initialised."

    def bid(self):
        print "Client", self.client_index, "is making a bid..."
        bid = input("Please input a bid price: ")
        while not self.is_bid_valid(bid):
            print "Invalid value!"
            bid = input("Please input a bid price: ")
        self.secret = bid

        u_secret = 0
        self.u_array = []
        for i in range(self.n):
            if i != self.secret:
                u_i = self.ZZp.random_element()
                u_secret += u_i
                self.u_array.append(u_i)
            else:
                self.u_array.append(0)
        u_secret = self.ZZp(u_secret)
        self.u_array[self.secret] = u_secret

        self.h_array = []
        for i in range(0, self.secret):
            h_i = self.h_bar_array[i] / (self.g ** self.u_array[i])
            self.h_array.append(h_i)
        h_secret = self.g ** self.u_array[self.secret]
        self.h_array.append(h_secret)
        for i in range(self.secret + 1, self.n):
            h_i = self.h_bar_array[i - 1] / (self.g ** self.u_array[i])
            self.h_array.append(h_i)

        if self.verbose:
            print "Secret bid price of Client", self.client_index, "is", self.secret
            print "Random u values are", self.u_array
            print "Public h values are", self.h_array

    # check the bid price is a valid value (0 <= bid <= number of h_bar_array - 1)
    def is_bid_valid(self, bid):
        return (bid >= 0) and (bid <= self.n - 1)

    # the first step in DHOT
    # this step is for the client who acts as a 'receiver' in DHOT
    # simulating the process that the client send its public h values to the server
    def get_h_array(self):
        return self.h_array

    # the second step in DHOT
    # this step is for the client who acts as a 'sender' in DHOT
    # the client form a flag array using given random values generated by the server, and
    # encrypt the array using the peer's public h values given by the server
    def encrypt_flag_array(self, r_lt, r_eq, r_gt, h_array):
        flag_array = []
        for i in range(0, self.secret):
            flag_array.append(r_lt)
        flag_array.append(r_eq)
        for i in range(self.secret + 1, self.n):
            flag_array.append(r_gt)

        encrypted = []
        for i in range(self.n):
            r = self.ZZp.random_element()
            A = self.g ** r
            B = (h_array[i] ** r) * (self.g ** flag_array[i])
            encrypted.append((A,B))

        if self.verbose:
            print "Flag array:", flag_array
            print "Encrypted flag array using given h values:", encrypted

        return encrypted

    # the third step in DHOT
    # this step is for the client who acts as a 'receiver' in DHOT
    # the client is able to decrypt only one pair in the encrypted flag array
    # which has an index equals the client's secret (bid price)
    # the random value obtained after decryption does not give any information
    # before it is sent back to the sever
    # (it is not understood by the 'Receiver')
    def decrypt_flag(self, encrypted_flag_array):
        (A, B) = encrypted_flag_array[self.secret]
        u_secret = self.u_array[self.secret]
        ret = B / (A ** u_secret)
        if self.verbose:
            print "Decrypted Bs / As^us = ", ret
        return ret

# verbose mode for debugging
# s = Server(100, 3, 10, True)
s = Server(100, 3, 100)
s.begin_auction()









