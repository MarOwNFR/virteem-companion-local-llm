# Virteem Companion — Mode Local (Ollama + Ngrok)

Faites tourner un modèle d'IA open source **sur votre propre machine** et connectez-le à [Virteem Companion](https://github.com/pareaud/virteem-companion-v2). Vos données restent chez vous.

```
Votre machine                            Virteem Companion (Cloud)
┌─────────────────────────────┐          ┌──────────────────────────┐
│                             │          │                          │
│  Ollama  ──▶  Ngrok tunnel  │──HTTPS──▶│  Backend + Agent IA      │
│  (modèle)    (sécurisé)     │  token   │                          │
│                             │          │                          │
└─────────────────────────────┘          └──────────────────────────┘
```

Le modèle IA tourne en local. **Ngrok** crée un tunnel HTTPS sécurisé. Virteem Companion communique avec le modèle via ce tunnel, protégé par un token de sécurité.

---

## Prérequis

| Outil | Pourquoi | Lien |
|-------|----------|------|
| **Docker Desktop** | Fait tourner Ollama et Ngrok en conteneurs | [Installer Docker](https://docs.docker.com/desktop/) |
| **Compte Ngrok** (gratuit) | Crée le tunnel HTTPS entre votre machine et le cloud | [Créer un compte](https://ngrok.com) |

### Récupérer votre Ngrok Authtoken

1. Connectez-vous sur https://dashboard.ngrok.com
2. Menu de gauche → **Your Authtoken** (ou [lien direct](https://dashboard.ngrok.com/get-started/your-authtoken))
3. Cliquez **Copy** — le token ressemble à `2abc123_xYzAbCdEfGhIjKlMnOpQrStUv`

---

## Installation

### 1. Cloner ce dépôt

```bash
git clone https://github.com/pareaud/virteem-companion-local-llm.git
cd virteem-companion-local-llm
```

### 2. Configurer les variables d'environnement

Copiez le fichier d'exemple et remplissez-le :

```bash
cp .env.example .env
```

Ouvrez `.env` dans un éditeur de texte :

```env
# OBLIGATOIRE — Votre token Ngrok (récupéré sur https://dashboard.ngrok.com)
NGROK_AUTHTOKEN=votre_token_ngrok_ici

# OBLIGATOIRE — Modèle IA à utiliser (voir tableau ci-dessous)
MODEL=qwen2.5:1.5b

# OPTIONNEL — Token de sécurité fixe (si non défini, un nouveau est généré à chaque lancement)
# VIRTEEM_TOKEN=mon-token-personnalise
```

---

## Variables d'environnement

| Variable | Obligatoire | Description | Où la trouver |
|----------|:-----------:|-------------|---------------|
| `NGROK_AUTHTOKEN` | **Oui** | Token d'authentification Ngrok | [Dashboard Ngrok → Your Authtoken](https://dashboard.ngrok.com/get-started/your-authtoken) |
| `MODEL` | Non | Nom du modèle Ollama à télécharger (défaut : `llama3.2:3b`) | Voir le tableau des modèles ci-dessous |
| `VIRTEEM_TOKEN` | Non | Token de sécurité pour protéger l'accès au modèle. Si non défini, un token aléatoire est généré à chaque lancement | Affiché dans le terminal après le lancement du script |

### Choisir un modèle

| Modèle | Taille disque | RAM requise | GPU nécessaire ? | Tool calling | Idéal pour |
|--------|:------------:|:-----------:|:----------------:|:------------:|------------|
| `qwen2.5:0.5b` | ~400 Mo | ~1 Go | Non | Oui | Ultra-léger, test minimal |
| `qwen2.5:1.5b` | ~1 Go | ~2 Go | Non | Oui | Petite machine, CPU only |
| `qwen2.5:3b` | ~2 Go | ~4 Go | Non | Oui | Bon compromis en CPU |
| `llama3.2:3b` | ~2 Go | ~4 Go | Non | Oui | Alternative Llama en CPU |
| `mistral` (7B) | ~4 Go | ~8 Go | Recommandé | Oui | Bon en français, rapide avec GPU |
| `llama3.1` (8B) | ~5 Go | ~10 Go | Recommandé | Oui | Performant, usage courant |
| `qwen2.5` (7B) | ~4 Go | ~8 Go | Recommandé | Oui | Multilingue, performant |
| `llama3.1:70b` | ~40 Go | ~48 Go | Obligatoire | Oui | Production, très performant |

> **Sans GPU NVIDIA ?** Choisissez `qwen2.5:1.5b` ou `qwen2.5:3b`. Les réponses seront plus lentes (10–60 secondes) mais tout fonctionne en CPU pur.
>
> **Avec GPU NVIDIA ?** Ollama le détecte et l'utilise automatiquement. Vous pouvez choisir des modèles plus gros (7B+). Installez [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) si ce n'est pas déjà fait.

---

## Lancement

### Windows — PowerShell (recommandé)

```powershell
.\start-test-ngrok-cpu.ps1
```

### Windows — CMD

```cmd
start.bat
```

### Linux / macOS

```bash
chmod +x start.sh
./start.sh
```

### Ollama seul (sans Ngrok, pour usage local uniquement)

```powershell
.\start-ollama-cpu.ps1
```

Le script va :
1. Démarrer le serveur Ollama dans Docker
2. Télécharger le modèle (uniquement la première fois — peut prendre plusieurs minutes)
3. Lancer le tunnel Ngrok
4. Afficher les informations de connexion

### Résultat attendu

```
========================================
  COLLEZ DANS VIRTEEM COMPANION (Local)
========================================

  URL serveur :  https://xxxxx-xxxxx.ngrok-free.dev
  Token        :  a1b2c3d4e5f6...
  Modèle       :  qwen2.5:1.5b
========================================
```

**Gardez cette fenêtre ouverte** — le serveur doit rester actif pendant l'utilisation.

---

## Configuration dans Virteem Companion

1. Ouvrez **Virteem Companion** dans votre navigateur
2. Sélectionnez votre agent dans le header
3. Allez dans **Inférence → Modèles**
4. Cliquez sur **Local / Open Source** (icône Ollama)
5. Remplissez :
   - **URL du serveur Ngrok** → collez l'URL `https://xxxxx.ngrok-free.dev` affichée dans le terminal
   - **Token de sécurité** → collez le token affiché dans le terminal
6. Cliquez **Tester** — le voyant doit passer au vert
7. Sélectionnez votre modèle dans la liste déroulante
8. Activez **Support du tool calling** si votre modèle le supporte (Qwen, Llama 3.x, Mistral)
9. Cliquez **Sauvegarder**

---

## Où trouver ses clés et informations

| Information | Où la trouver |
|-------------|---------------|
| **Ngrok Authtoken** | [dashboard.ngrok.com → Your Authtoken](https://dashboard.ngrok.com/get-started/your-authtoken) |
| **URL du tunnel** | Affichée dans le terminal après lancement, ou sur http://localhost:4040 |
| **Token de sécurité** | Affiché dans le terminal. Généré automatiquement à chaque démarrage sauf si `VIRTEEM_TOKEN` est défini dans `.env` |
| **Modèle actif** | Affiché dans le terminal, ou via `docker compose exec ollama ollama list` |

---

## Commandes utiles

```bash
# Voir les conteneurs en cours
docker ps

# Voir les logs en temps réel
docker compose logs -f

# Suivre le téléchargement du modèle
docker compose logs -f model-loader

# Lister les modèles installés
docker compose exec ollama ollama list

# Ajouter un modèle supplémentaire
docker compose exec ollama ollama pull mistral

# Arrêter tout
docker compose --profile tunnel down

# Arrêter et supprimer les modèles (libérer l'espace disque)
docker compose --profile tunnel down -v

# Dashboard Ngrok (stats, URL, requêtes)
# http://localhost:4040
```

---

## Compatibilité des fonctionnalités

| Fonctionnalité | Cloud (OpenAI/Anthropic) | Local (Ollama) | Notes |
|---|:---:|:---:|---|
| Chat | Oui | Oui | |
| Streaming | Oui | Oui | |
| System prompt | Oui | Oui | |
| Tool calling (outils, web search, RAG) | Oui | Selon le modèle | Qwen, Llama 3.x, Mistral : oui |
| Génération d'images | Oui | Non | Nécessite OpenAI (DALL-E) |
| Vision (analyse d'images) | Oui | Partiel | Uniquement `llama3.2-vision` |

Si votre modèle ne supporte pas le tool calling, désactivez le toggle **Support du tool calling** dans la configuration. Le chat fonctionnera en mode direct sans outils.

---

## Résolution de problèmes

### "ERREUR: définissez NGROK_AUTHTOKEN"

Le fichier `.env` ne contient pas de token Ngrok.

- Vérifiez que `.env` existe (copié depuis `.env.example`)
- Vérifiez que `NGROK_AUTHTOKEN=` est renseigné
- Récupérez votre token sur https://dashboard.ngrok.com/get-started/your-authtoken

### Le bouton "Tester" affiche une erreur

- Vérifiez que **Docker Desktop est lancé**
- Vérifiez que le **script tourne toujours** (ne fermez pas le terminal)
- Ouvrez http://localhost:4040 — si la page ne charge pas, Ngrok n'est pas actif
- Relancez le script

### "Token de sécurité invalide" (erreur 403)

Le token dans Virteem Companion ne correspond pas à celui du script.

- Recopiez le token exactement tel qu'affiché dans le terminal
- Si vous avez relancé le script, un nouveau token a été généré
- Pour un token permanent, définissez `VIRTEEM_TOKEN` dans `.env`

### Les réponses sont très lentes

C'est normal en mode CPU.

- Utilisez un modèle plus petit (`qwen2.5:1.5b`)
- Si vous avez un **GPU NVIDIA**, installez [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- Fermez les applications gourmandes en mémoire

### "Out of memory"

- Passez à un modèle plus petit dans `.env` : `MODEL=qwen2.5:1.5b`
- Vérifiez la RAM disponible (minimum 2 Go libres pour les modèles 1.5B)

---

## Sécurité et confidentialité

- Le modèle IA tourne **entièrement sur votre machine**
- Le tunnel Ngrok est **chiffré en HTTPS** (TLS)
- Chaque requête est protégée par un **token de sécurité** vérifié avant d'atteindre le modèle
- Ngrok ne stocke aucune donnée de conversation
- Pour un usage en production, envisagez un [plan Ngrok payant](https://ngrok.com/pricing) (domaine fixe, pas de limite de bande passante)

---

## Structure du projet

```
.
├── .env.example              # Variables d'environnement (à copier en .env)
├── docker-compose.yml        # Services Docker (Ollama + Ngrok + model-loader)
├── start.sh                  # Script de lancement Linux / macOS
├── start.bat                 # Script de lancement Windows CMD
├── start-ollama-cpu.ps1      # Ollama seul en CPU (sans Ngrok)
├── start-test-ngrok-cpu.ps1  # Ollama + Ngrok en CPU (PowerShell)
└── README.md                 # Ce fichier
```


