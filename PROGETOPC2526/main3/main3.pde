


import processing.net.*;
import java.util.*;
import java.util.concurrent.locks.Condition;
import java.util.concurrent.locks.ReentrantLock;


Client c;                           // ligação TCP com o servidor Erlang
int state = 0;                      // ecrã atual: 0=Login, 1=Fila de espera, 2=Jogo
String serverMsg = "";              // mensagem de erro ou aviso do servidor
ArrayList<PlayerInfo> players = new ArrayList<PlayerInfo>();   // lista de jogadores recebidos
ArrayList<ObjectInfo> objects = new ArrayList<ObjectInfo>();   // lista de objetos (comida/veneno)
ArrayList<TopPlayer> topPlayers = new ArrayList<TopPlayer>();
String terminalBuffer = "";         // buffer para escrever comandos no ecrã de login
String myUsername = "";             // nome do jogador local (capturado no LOGIN)
final Object lock = new Object();

// Flags para movimento contínuo (enquanto a tecla está premida)
boolean leftFlag = false, rightFlag = false, forwardFlag = false;


void setup() {
  size(800, 600);                                    // janela 800x600
  c = new Client(this, "127.0.0.1", 12345);         // liga ao servidor local na porta 12345
  println("Conectado ao servidor!");

  Thread t = new Thread(() -> {
  while (true) {
    if (c != null && c.available() > 0) {
      String raw = c.readStringUntil('\n');
      if (raw != null) handleServerMessage(raw.trim());
    }
    try { Thread.sleep(5); } catch (InterruptedException e) {}
  }
});
t.setDaemon(true);
t.start();
}


void draw() {
  background(30);                    // fundo escuro
  // --- 2. Enviar comandos de movimento CONTINUAMENTE se as teclas estiverem premidas ---
  if (state == 2) {
    if (leftFlag)   c.write("LEFT\n");
    if (rightFlag)  c.write("RIGHT\n");
    if (forwardFlag) c.write("FORWARD\n");
  }

  // --- 3. Desenhar o ecrã correto de acordo com o estado ---
  if (state == 0) {
    drawLoginScreen();
  } else if (state == 1) {
    drawQueueScreen();
  } else if (state == 2) {
    drawGameScreen();
  }
}

void handleServerMessage(String msg) {
  println("Servidor diz: " + msg);    // mostra no terminal (debug)
  
  if (msg.startsWith("(TOP)")) {
    parseTop(msg);
    return;
  }
  if (msg.equals("<ENTRASTE>")) {
    // Login bem-sucedido → muda para ecrã de espera e entra na fila
    state = 1;
    c.write("JOIN\n");
  } else if (msg.equals("GAME_START")) {
    // A partida começou → muda para ecrã de jogo
    state = 2;
  } else if (msg.equals("GAME_OVER")) {
    // A partida terminou → volta à fila automaticamente
    state = 1;
    leftFlag = rightFlag = forwardFlag = false;   // para enviar comandos "fantasma"
    c.write("JOIN\n");
  } else if (msg.startsWith("(ERROR)")) {
    // Mostra erro no ecrã de login
    serverMsg = msg;
  } else if (state == 2) {
    // Durante o jogo, as mensagens são o estado do mundo (jogadores + objetos)
    parseGameState(msg);
  }
}


void parseTop(String msg) {

  String cleanMsg = msg.replace("(TOP)", "").trim();

    topPlayers.clear();
    
    // Remove o "\n" do fim e verifica se a mensagem não está vazia
    msg = cleanMsg.trim();
    if (msg.isEmpty()) return;
    
    // Corta a string em cada jogador (separados por ;)
    String[] players = msg.split(";");
    
    for (String playerStr : players) {
        // Corta os dados do jogador (Nome,Score)
        String[] data = playerStr.split(",");
        
        if (data.length == 2) {
            String name = data[0];
            int score = Integer.parseInt(data[1]);
            
            topPlayers.add(new TopPlayer(name, score));
        }
    }
}

// Formato: P,Nome,x,y,angulo,massa,score|P,...|O,F/V,x,y,raio|O,...
void parseGameState(String msg) {
  ArrayList<PlayerInfo> newPlayers = new ArrayList<PlayerInfo>();
  ArrayList<ObjectInfo> newObjects = new ArrayList<ObjectInfo>();

  String[] parts = split(msg, '|');           // separa pelo símbolo '|'
  for (String p : parts) {
    if (p.length() == 0) continue;
    String[] d = split(p, ',');               // cada parte separada por ','
    if (d.length == 0) continue;

    if (d[0].equals("P") && d.length >= 7) {
      newPlayers.add(new PlayerInfo(d[1], float(d[2]), float(d[3]), float(d[4]), float(d[5]), int(d[6])));
    } else if (d[0].equals("O") && d.length >= 5) {
      newObjects.add(new ObjectInfo(d[1], float(d[2]), float(d[3]), float(d[4])));
    }
  }
  synchronized(lock) {
    players = newPlayers;
    objects = newObjects;
  }
  println("Jogadores: " + players.size() + "  Objetos: " + objects.size());
}

void keyPressed() {
  if (state == 0) {
    // ---------- ECRÃ DE LOGIN ----------
    if (key == ENTER || key == RETURN) {
      if (terminalBuffer.length() > 0) {
        // Extrai o username se for comando LOGIN:username:password
        String[] loginParts = split(terminalBuffer, ':');
        if (loginParts.length >= 2 && loginParts[0].equals("LOGIN")) {
          myUsername = loginParts[1];
        }
        c.write(terminalBuffer + "\n");
        println("Enviado: " + terminalBuffer);
        terminalBuffer = "";
      }
    } else if (key != CODED) {
      terminalBuffer += key;       // acumula caracteres digitados
    }
  } else if (state == 2) {
    // Ativa flags (o envio real é feito no draw())
    if (key == 'w' || keyCode == UP)    forwardFlag = true;
    if (key == 'a' || keyCode == LEFT)  leftFlag = true;
    if (key == 'd' || keyCode == RIGHT) rightFlag = true;
  }
}

void keyReleased() {
  if (state == 2) {
    // Desativa as flags quando a tecla é solta
    if (key == 'w' || keyCode == UP)    forwardFlag = false;
    if (key == 'a' || keyCode == LEFT)  leftFlag = false;
    if (key == 'd' || keyCode == RIGHT) rightFlag = false;
  }
}

void drawLoginScreen() {
  textAlign(CENTER);
  fill(255);
  text("ECRÃ DE LOGIN", width/2, height/2 - 40);
  text("Digita o comando (ex: LOGIN:Alice:123)", width/2, height/2);
  fill(255, 0, 0);
  text(serverMsg, width/2, height/2 + 40);    // mensagem de erro
  fill(255);
  text(terminalBuffer, width/2, height/2 + 80); // mostra o que estás a escrever
}

void drawQueueScreen() {
    textAlign(CENTER);
    fill(255, 255, 0);
    text("NA FILA DE ESPERA...", width/2, 50);
    text("À espera de jogadores (mínimo 3)...", width/2, 70);
    
    fill(255);
    text("Top de pontuações:", width/2, 110);
    for (int i = 0; i < topPlayers.size(); i++) {
        TopPlayer tp = topPlayers.get(i);
        text(tp.name + "  " + tp.score, width/2, 130 + i * 20);
    }
}


void drawGameScreen() {

  
  ArrayList<PlayerInfo> snapP;
  ArrayList<ObjectInfo> snapO;
  synchronized(lock) {
    snapP = new ArrayList<PlayerInfo>(players);
    snapO = new ArrayList<ObjectInfo>(objects);
  }

  for (ObjectInfo obj : snapO) {
    if (obj.type.equals("F")) {
      fill(0, 255, 0);                // verde para comida
    } else {
      fill(255, 0, 0);                // vermelho para veneno
    }
    noStroke();
    ellipse(obj.x, obj.y, obj.size * 2, obj.size * 2);  // círculo com diâmetro 2*raio
  }


  snapP.sort((p1, p2) -> Float.compare(p1.mass, p2.mass)); // desenhar o gajo pequeno pro grande naqueles pique
  for (PlayerInfo p : snapP) {
    pushMatrix();
    translate(p.x, p.y);              // move o sistema de coordenadas para o centro do jogador

    // Raio visual = sqrt(mass / PI)  --> igual à hitbox real do servidor
    float r = (float)(Math.sqrt(p.mass / Math.PI));

    fill(0);
    // Borda azul para o próprio, vermelha para os outros
    if (p.name.equals(myUsername)) {
      stroke(0, 0, 255);              // azul
    } else {
      stroke(255, 0, 0);              // vermelho
    }
    strokeWeight(2);
    ellipse(0, 0, r * 2, r * 2);      // desenha o círculo do jogador

    // Linha de direção (indica para onde o jogador está virado)
    rotate(p.angle);
    stroke(255);                       // branca
    line(0, 0, r, 0);

    // Nome e pontuação (desenha fora da rotação)
    rotate(-p.angle);
    fill(255);
    textAlign(CENTER);
    text(p.name, 0, -r - 5);           // nome por cima do círculo
    text("Score: " + p.score, 0, r + 12); // score por baixo

    popMatrix();
  }
}

class PlayerInfo {
  String name;
  float x, y, angle;
  float mass;
  int score;

  PlayerInfo(String n, float x, float y, float a, float m, int s) {
    name = n; this.x = x; this.y = y; angle = a; mass = m; score = s;
  }
}

class ObjectInfo {
  String type;   // "F" (food) ou "V" (veneno)
  float x, y, size;  // size = raio do objeto

  ObjectInfo(String t, float x, float y, float s) {
    type = t; this.x = x; this.y = y; size = s;
  }
}

class TopPlayer {
    String name;
    int score;
    TopPlayer(String n, int s) { name = n; score = s; }
}