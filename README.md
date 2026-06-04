# Multiplayer Game - Concurrent Programming Project

A real-time multiplayer game project built to explore concurrent programming concepts. Players connect to a server, join matches, and interact in a 2D game world together.

## What is this?

This is a university project for a Concurrent Programming course. We built a system where multiple players can play together at the same time through a network connection. Think of it like a simple online game where you can move around, interact with other players, and compete for points.

## How it works

**The Server** (written in Erlang)
- Manages player connections and keeps track of who's online
- Matches players together to start games
- Runs the game logic for all active matches
- Makes sure everyone sees the same game state
- Uses lightweight processes to handle many players at once

**The Client** (written in Java with Processing)
- Shows you the game on your screen
- Lets you control your character with keyboard/mouse
- Sends your actions to the server
- Receives updates about what other players are doing
- Displays the game world in real-time

**How they talk to each other**
- They communicate through TCP network sockets
- Messages are sent back and forth continuously
- The server tells clients what's happening in the game
- Clients tell the server what the player is doing

## Project structure

```
├── PROGETOPC2526/
│   ├── main1/ to main5/          ← Client code (Java/Processing)
│   │                               Different versions/implementations
│   └── Servidor/                 ← Server code (Erlang modules)
│       ├── tcp_server.erl        ← Main server, accepts connections
│       ├── matchmaker.erl        ← Pairs up players for games
│       ├── game_session.erl      ← Runs individual game matches
│       ├── client_handler.erl    ← Handles each player's connection
│       ├── top_manager.erl       ← Overall game coordinator
│       └── ut_manager.erl        ← Manages user login/logout
│
└── Relatório/                    ← Project report (Portuguese)
```

## The game features

- **User accounts**: Sign in to play
- **Matchmaking**: The server pairs you with other players
- **Real-time gameplay**: Move your character in a 2D world
- **Player interaction**: Interact with other players
- **Scoring system**: Compete and earn points
- **Multiple games**: Many matches can happen at the same time

## Technologies used

- **Erlang**: Powers the server with lightweight concurrent processes
- **Java**: Client application
- **Processing**: Graphics library for the game interface
- **TCP/IP**: Network communication

## Key concepts demonstrated

- Concurrent process management (Erlang actors)
- Network communication and synchronization
- Real-time game state updates
- Multi-client connection handling
- Game loop and state consistency

## Project team

- Miguel Gonçalves
- João Taveira
- José Novais
- Luís Lopes

Built for the Concurrent Programming course at University of Minho
