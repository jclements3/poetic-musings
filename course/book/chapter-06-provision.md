# Chapter 6 — Zone 6: PROVISION

*The Wheel — What Does Not Need To Be Reinvented*

---

## 1. Why this zone matters

There is a specific failure mode every infrastructure team eventually hits, and it
has a name even if nobody writes it on the whiteboard: **console drift**. Someone
needs a security group opened for a demo. They click into the AWS console, add the
rule, ship the demo, and forget. Three months later a security review finds a
0.0.0.0/0 ingress rule on port 22 that nobody can explain, attached to nobody's
pull request, described in nobody's runbook. The engineer who made it has since
left. This isn't a hypothetical — it is the default outcome of letting
infrastructure be something people *do* rather than something people *write down*.

Clicking through a cloud console is fast, which is exactly the problem. It produces
infrastructure with no diff, no reviewer, no audit trail beyond a CloudTrail event
buried in a log bucket nobody reads until after the incident. It cannot be
reproduced deterministically — ask two engineers to "set up the VPC the same way"
by hand and you will get two different VPCs, with subtly different CIDR blocks, a
forgotten route table association, an inconsistent tag. And it cannot be diffed
against intent: there is no way to ask "does what's actually running match what we
decided should be running" without manually re-clicking through every screen and
comparing by eye.

**Reproducibility is the actual point of Infrastructure as Code.** Not "it's
faster" (it often isn't, for a one-off change), not "it's trendy." The point is
that infrastructure becomes a text artifact: version-controlled, reviewable in a
pull request, diffable against the last known-good state, and re-creatable from
scratch by running the same command twice and getting the same result. That
property — same input, same output, every time — is what makes an environment
*trustworthy* in a way a console click-through never can be, and it's what makes a
security review of "what does our infrastructure actually look like" a `git diff`
instead of an archaeology project.

Zone 6 is where this happens in two distinct layers, and the distinction matters
enough that it's a standard interview question (see §6): **Terraform provisions —
it answers "does the infrastructure exist, in the shape I declared."** **Ansible
configures — it answers "is the right software deployed and running correctly on
that infrastructure, every single time I check."** Confusing the two, or trying to
make one tool do both jobs badly, is one of the most common architectural mistakes
in this zone.

## 2. Terraform deep dive

### Providers, resources, and state — precisely

Three concepts do all the work in Terraform, and getting the mental model right up
front prevents a lot of confusion later.

A **provider** is a plugin that translates Terraform's declarative HCL into API
calls against a specific platform — `aws`, `azurerm`, `google`, `kubernetes`,
`docker`. It's declared with a required version constraint (pinning matters: an
unpinned provider can silently change behavior between runs) and configured with
credentials and defaults like region:

```hcl
# providers.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
```

A **resource** is one declared unit of infrastructure that provider knows how to
create, read, update, or destroy — a VPC, an S3 bucket, an IAM role. Each resource
block has a type and a local name (`aws_s3_bucket.artifacts`), and Terraform builds
a dependency graph from the references between them, not from the order they're
written in the file.

**State** is the part people underestimate. Terraform doesn't re-derive the world
by querying the provider fresh on every run (a few resources support partial
drift-detection refresh, but that's not the primary mechanism) — it keeps a JSON
file, `terraform.tfstate`, that maps every resource block to the real-world object
it created (an actual VPC ID, an actual ARN) and records the last-known attributes
of that object. `plan` computes a diff between three things: the HCL you wrote, the
state file's record of what was last applied, and (for supported resources) a
refreshed read of the real object. Losing the state file, or having two people run
`apply` against different copies of it, is how you get orphaned resources,
duplicate resources, or Terraform confidently trying to recreate something that
already exists. This is precisely why local state is dangerous for teams — more on
this below.

### File layout convention

There's no technical requirement Terraform enforces here, but the convention is
followed for a reason: it lets any engineer open an unfamiliar Terraform root and
know exactly where to look.

```
infra/terraform/
├── backend.tf         # where state lives (S3+DynamoDB, or azurerm equivalent)
├── providers.tf        # provider blocks + version pins
├── variables.tf          # every input variable, with type + description
├── outputs.tf              # every value exposed to callers/CI (ARNs, URLs, IDs)
├── main.tf                  # resource/module wiring — the actual shape
├── modules/
│   └── aws-platform/          # a reusable, self-contained unit
└── environments/
    ├── dev/terraform.tfvars     # dev-sized values fed into the SAME modules
    └── prod/terraform.tfvars    # prod-sized values, same code path
```

`variables.tf` and `outputs.tf` are the *interface* of a root module or child
module — what goes in, what comes out — kept separate from `main.tf` so the
interface is reviewable at a glance without reading resource logic.

### The plan → apply → destroy lifecycle

```bash
terraform init      # downloads providers, configures the backend
terraform validate  # syntax + internal consistency check, no credentials needed
terraform plan  -var-file=environments/dev/terraform.tfvars   # computes the diff, changes nothing
terraform apply -var-file=environments/dev/terraform.tfvars   # executes the diff
terraform destroy -var-file=environments/dev/terraform.tfvars # tears it all down
```

`plan` is the safety net that makes this whole model work: it is a dry run that
shows exactly what will be added, changed in place, or destroyed-and-recreated,
*before* anything happens. A disciplined team treats an unreviewed `apply` — one
nobody ran `plan` on first, or whose plan output nobody read — as a near-miss
worth a postmortem, not a normal Tuesday.

### Remote state, and why local state is dangerous for teams

If `terraform.tfstate` lives on one engineer's laptop, you get exactly the failure
mode IaC is supposed to prevent: nobody else's `plan` matches reality, two people
running `apply` in the same afternoon can clobber each other's changes with no
warning, and losing the laptop means losing the only record of what's actually
been created. The fix is a remote backend with locking:

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "poetic-musings-tfstate"
    key            = "platform/terraform.tfstate"
    region         = "us-east-2"
    dynamodb_table = "poetic-musings-tf-locks"
    encrypt        = true
  }
}
```

The S3 bucket holds the actual state file (versioned, so a bad apply's prior state
is recoverable; SSE-encrypted, since state files routinely contain sensitive
values like database passwords in plaintext). The DynamoDB table exists for one
purpose: **locking**. When `terraform apply` starts, it writes a lock item to that
table; a second `apply` started concurrently by someone else will refuse to run
until the lock clears. Without this, two simultaneous applies race against the
same state file and corrupt it. This repo's `backend.tf` documents the exact
bootstrap commands for creating that bucket and table, and — deliberately — leaves
the backend block itself commented out, so `terraform init`/`validate` still work
in CI without requiring pre-existing AWS infrastructure or live credentials on
every PR.

The `azurerm` alternative follows the same shape, authenticating with Azure AD
instead of a shared storage account key (`use_azuread_auth = true`) — worth
knowing because a shared key is a long-lived secret sitting outside any identity
system, exactly the kind of credential a security review should flag on sight.

### Data sources

A **data source** reads information about a resource Terraform doesn't manage —
existing infrastructure created elsewhere, or a platform-computed value like the
current account ID or region:

```hcl
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# used later to build an ARN or scope a policy without hardcoding an account number
```

This is how you reference the current AWS account ID in an IAM policy without
typing a literal 12-digit number into source control — a small thing that prevents
a whole class of copy-paste errors when the same module runs against different
accounts.

### `terraform import`

Real environments almost never start from zero. `terraform import` lets you adopt
a resource that already exists — created by hand, by a previous tool, by a
different team — into Terraform's state, associating it with a resource block you
write to match its current real attributes:

```bash
terraform import aws_s3_bucket.artifacts poetic-musings-artifacts-prod
```

The gotcha: `import` only populates state. It does not generate the HCL for you
(newer Terraform versions can generate a starting config with `terraform plan
-generate-config-out=`, but it's not automatic in older workflows) — you still
have to write a resource block whose declared attributes match reality closely
enough that the next `plan` doesn't propose destroying and recreating the thing
you just imported. Getting that config wrong is one of the more common ways a
first `import` goes sideways.

### Provisioners — and why HashiCorp says avoid them

`local-exec` runs a command on the machine running Terraform; `remote-exec` runs a
command on the newly created resource over SSH or WinRM:

```hcl
resource "aws_instance" "app" {
  # ...
  provisioner "remote-exec" {
    inline = ["sudo apt-get update", "sudo apt-get install -y nginx"]
  }
}
```

HashiCorp's own documentation recommends provisioners as a **last resort**, and
the reasoning holds up: they step outside Terraform's declarative model into
imperative shell execution that Terraform can't reason about, can't diff, and
can't safely retry — a failed provisioner can leave a resource half-configured
with no clean way to converge back to a known state on the next apply. This is
precisely the seam where Terraform's job should end and Ansible's job should
begin (§6): provision the instance with Terraform, then hand it to Ansible — or a
purpose-built image via Packer — to actually configure the software on it.
Provisioners exist for the rare case (bootstrapping something that genuinely has
no other hook) but reaching for one by default is a design smell.

### Modules and reusability

A module is just a directory of `.tf` files with its own `variables.tf` and
`outputs.tf`, called from elsewhere with a `source` and a set of inputs:

```hcl
# main.tf (root)
module "aws_platform" {
  source       = "./modules/aws-platform"
  name_prefix  = "poetic-musings-${var.environment}"
  vpc_cidr     = var.vpc_cidr
  tags         = local.common_tags
}
```

The value isn't abstraction for its own sake — it's that the VPC/ECR/KMS/IAM shape
gets defined once, reviewed once, security-scanned once, and then every
environment that needs "one of these" calls the same module with different
inputs instead of copy-pasting HCL and letting the copies drift apart silently.

### Multi-environment strategy: workspaces vs. separate tfvars vs. separate state

Three real approaches exist, and picking the wrong one for your team size is a
common mistake:

- **Terraform workspaces** (`terraform workspace new prod`) give you multiple
  state files under one root module, switched with a CLI command. Lightweight,
  but the isolation is soft: it's easy to run a command against the wrong
  workspace by mistake because the workspace is invisible in the code itself, and
  all workspaces still share the same backend configuration and the same blast
  radius if that backend is misconfigured.
- **Separate `.tfvars` per environment, same module tree, same state backend
  config but different state *keys*** — this repo's approach
  (`environments/dev/terraform.tfvars`, `environments/prod/terraform.tfvars`)
  feeding the same root module. The environment is explicit in every command
  (`-var-file=environments/prod/terraform.tfvars`), which makes it much harder to
  apply to the wrong environment by accident, at the cost of a slightly longer
  command line every time.
- **Fully separate state, fully separate root modules per environment** — the
  heaviest option, used when environments genuinely diverge in shape (not just
  size), or when different teams own different environments and shouldn't share
  even the possibility of touching each other's state. Most reuse benefit then has
  to come from shared child modules rather than a shared root.

For small-to-mid teams, "separate tfvars, same modules, state key includes the
environment name" is the sweet spot: real isolation, real explicitness in the
command line, without the fragmentation of maintaining N independent root
modules.

### EKS cluster creation with Terraform

Standing up an EKS cluster with Terraform is a real, common task and worth naming
the shape even where this repo hasn't done it: an `aws_eks_cluster` resource
referencing a control-plane IAM role and the VPC subnets, one or more
`aws_eks_node_group` resources (or a Karpenter/Fargate profile) for compute, an
OIDC identity provider resource so pods can assume IAM roles via IRSA, and — this
is the part people get bitten by — the `aws-auth` ConfigMap (or, on current EKS,
native `aws_eks_access_entry` resources) mapping IAM principals to Kubernetes
RBAC groups, since creating the cluster is not the same as being able to
authenticate against it with `kubectl`. This is squarely Zone 6/Zone 7 overlap:
Terraform provisions the cluster and node infrastructure; what actually runs
inside it is Zone 7's territory.

## 3. Applied to poetic-musings: a real apply, a real bug, a real teardown

The AWS side of `infra/terraform/` in this repo was not just written and
`validate`d — it was applied for real, against a personal free-tier AWS account
(`us-east-2`), with 33 planned resources actually created: a VPC across two
availability zones, an ECR repository with image scanning and immutable tags, a
KMS-encrypted S3 artifacts bucket with a separate access-log bucket, a
customer-managed KMS key with rotation enabled, and a least-privilege IAM role for
CI pushes scoped to the exact ECR repo and S3 bucket ARNs the module created — not
a wildcard resource.

**The bug, in detail.** After `terraform apply` created the VPC flow-log
CloudWatch log group, it failed with:

```
Error: creating CloudWatch Logs Log Group: AccessDeniedException: The specified
KMS key does not exist or is not allowed to be used
    on modules/aws-platform/logs.tf line 12, in resource
    "aws_cloudwatch_log_group" "vpc_flow_logs":
```

The KMS key existed — `terraform validate` and `tfsec` both saw nothing wrong with
the HCL, and they were right, because nothing about the syntax or schema was
wrong. The problem was semantic and only visible at the API level: the key's
policy granted full access to the AWS account root principal (the default
Terraform generates if you don't write a custom policy), but CloudWatch Logs
encrypts log data as a *different* IAM principal — the `logs.<region>.amazonaws.com`
service principal — which the account-root statement does not cover. A customer-
managed KMS key needs an **explicit** statement authorizing that service
principal before CloudWatch Logs can use it to encrypt a log group. This is a
common enough trap that it's worth internalizing as a general rule: "account root
has full access" in a KMS key policy is not the same as "every AWS service that
might want to use this key can use it" — each service principal that needs the
key has to be named.

**The fix**, in `modules/aws-platform/kms.tf`, was a proper
`aws_iam_policy_document` with two statements instead of one — account-root
access, plus a scoped grant for the logs service principal, constrained with an
`ArnLike` condition on `kms:EncryptionContext:aws:logs:arn` so the grant only
applies to log groups in this account:

```hcl
data "aws_iam_policy_document" "platform_key" {
  statement {
    sid     = "AccountRootFullAccess"
    effect  = "Allow"
    principals { type = "AWS"; identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"] }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*",
                 "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}
```

A second `apply` with the corrected key policy succeeded. Every resource was then
independently verified against the live AWS API — not just trusted because
`apply` exited 0 — with `aws ecr describe-repositories`, `aws ec2 describe-vpcs`,
`aws s3api list-buckets`, and `aws kms describe-key`, and finally torn down
cleanly with `terraform destroy`.

**The lesson generalizes**: this is exactly the class of bug that static analysis
cannot catch, because the HCL was syntactically and schematically valid the whole
time — `tfsec` had nothing to flag, `terraform validate` had nothing to flag. It
only failed at the API layer, when a real service tried to use a real key under
real IAM semantics. That is the actual argument for applying infrastructure code
for real at least once in a disposable account, rather than trusting
`plan`/`validate`/`tfsec` as sufficient proof that the code works — they prove the
code is *well-formed*, not that it's *correct*.

**The Azure gap, stated honestly.** The `azure-platform` module is written and
passes `terraform validate` cleanly, but it has never been applied, because there
is no Azure subscription available to apply it against. Worth noting precisely
why this is a real limitation and not a cosmetic one: `terraform init` cannot even
configure the `azurerm` provider without valid credentials, because the provider
authenticates during `terraform init`/`configure` regardless of whether any
Azure resources end up being created — setting `-var enable_azure=false` does not
work around this, since the provider block itself still needs to initialize. A
validate-clean module is evidence the HCL is well-formed. It is not evidence it
works, for the same reason the KMS bug above demonstrates: correctness at the API
level can only be proven by actually calling the API. Anyone inheriting this code
should treat the Azure module as untested, not as "probably fine."

## 4. Ansible deep dive

### The agentless model, and why it matters for security posture

Ansible's defining architectural choice is that it requires no persistent agent
running on managed hosts. It connects over SSH (or WinRM for Windows), pushes a
small Python payload, executes it, and disconnects — nothing stays resident. This
is a real security-posture difference from agent-based tools: there's no
always-on daemon on every managed host that is itself an attack surface, no agent
credential to rotate or compromise, no agent version to keep patched across a
fleet. The tradeoff is that Ansible needs SSH reachability and Python on the
target, and its "push" model (a control node reaching out) doesn't scale the same
way a "pull" model does for very large, frequently-changing fleets — but for the
security posture question specifically, agentless-over-SSH is a genuinely smaller
footprint than a permanently-installed agent, and it's worth being able to state
that plainly in an interview rather than just naming the feature.

### Modules vs. ad-hoc commands

An ad-hoc command runs one module against inventory hosts directly, no playbook:

```bash
ansible all -i inventory.ini -m ping
ansible webservers -i inventory.ini -m shell -a "systemctl status nginx"
```

Useful for one-off checks. The actual unit of real work is the **module** — a
purpose-built, idempotent unit like `community.docker.docker_compose_v2`,
`ansible.builtin.copy`, `ansible.builtin.user` — versus reaching for `shell:` or
`command:` to wrap an imperative CLI call. The distinction matters for the same
reason it matters in Terraform's provisioner section: a real module knows how to
check current state and only act if it differs from desired state (the actual
mechanism behind idempotency); a raw `shell:` call is a black box that Ansible
can't reason about and that will happily re-run and "succeed" every single time
regardless of whether anything actually changed.

### Plays, playbooks, roles, collections

A **play** maps a set of hosts to a list of tasks. A **playbook** is a YAML file
of one or more plays:

```yaml
# playbook.yml
- hosts: observability
  become: true
  roles:
    - observability_stack
```

A **role** is the reusable unit — a directory structure (`tasks/`, `handlers/`,
`templates/`, `defaults/`, `vars/`) that packages a coherent piece of
configuration so it can be applied to any set of hosts without rewriting it. A
**collection** is a distributable bundle of roles, modules, and plugins,
installed like a package (`ansible-galaxy collection install
community.docker`) — the mechanism that gets you a real, maintained
`docker_compose_v2` module instead of everyone hand-rolling their own `shell:`
wrapper around `docker compose`.

### Inventory: static and dynamic

Static inventory is a plain file naming hosts and groups:

```ini
# inventory.ini
[observability]
localhost ansible_connection=local

[webservers]
web01.internal ansible_user=deploy
web02.internal ansible_user=deploy

[webservers:vars]
ansible_ssh_private_key_file=~/.ssh/deploy_key
```

Dynamic inventory replaces the static file with a script or plugin that queries a
live source of truth — the AWS EC2 API, an Azure resource group, a CMDB — at run
time, so newly launched instances are automatically in scope without anyone
hand-editing a file:

```yaml
# aws_ec2.yml — dynamic inventory plugin config
plugin: amazon.aws.aws_ec2
regions: [us-east-2]
filters:
  tag:Environment: prod
keyed_groups:
  - key: tags.Role
    prefix: role
```

```bash
ansible-inventory -i aws_ec2.yml --graph   # verify what the plugin resolves
ansible-playbook -i aws_ec2.yml site.yml
```

Static inventory is fine for a small, stable set of hosts. Dynamic inventory is
what you actually need once infrastructure is elastic — otherwise the inventory
file itself becomes another thing that silently drifts from reality, the exact
failure mode Zone 6 exists to eliminate.

### Ansible Vault

Secrets don't belong in playbooks or inventory files in plaintext — `ansible-vault`
encrypts a file (or a single string) with a password or a KMS-backed key, and
Ansible transparently decrypts it at run time:

```bash
ansible-vault create group_vars/prod/secrets.yml
ansible-vault edit group_vars/prod/secrets.yml
ansible-playbook -i inventory.ini site.yml --ask-vault-pass
# or, non-interactively in CI:
ansible-playbook -i inventory.ini site.yml --vault-password-file .vault_pass
```

This repo's Ansible role does **not** use Vault, and that's stated plainly rather
than glossed over: the observability stack it deploys ships default
`admin/admin` Grafana credentials (documented in `observability/README.md`), so
nothing sensitive is actually being managed. That's an honest, low-stakes gap —
but it would be a real gap, not a stylistic one, the moment this playbook managed
anything with an actual credential in it, and the day-one checklist below tells
you to check for exactly that.

### Idempotency as Ansible's core promise — and how to actually verify it

Every Ansible module is supposed to be idempotent: running the same playbook
twice against the same target should produce the same end state, with the second
run reporting nothing changed. This is the property that lets you run a playbook
against a fleet on a schedule without fear, and it's also the property people
most often claim without proof. "It didn't error the second time" is not evidence
of idempotency — a module can succeed on every run while still doing real,
unnecessary work each time (restarting a service, rewriting a file with identical
content) if it isn't genuinely idempotent. The actual test is `changed=0` on a
warm rerun against unchanged desired state, which is exactly what §5 walks
through.

## 5. Applied to poetic-musings: real idempotency, proven not claimed

The `observability_stack` role in `ansible/` deploys the real Prometheus +
Grafana + status-service stack via `community.docker.docker_compose_v2`, then
verifies it end to end: it polls `status-service`'s `/healthz` until it returns
200, polls `/metrics` and asserts the real `http_requests_total` Prometheus
metric string is present in the response body (not a mocked check), and queries
Prometheus's own `/api/v1/targets` API to confirm Prometheus has actually scraped
`status-service` and marked it `health: up` — proving the metrics pipeline works
end to end, not just that a container process happens to be running.

The idempotency proof, run against genuinely different starting states and
captured to log files in the same directory:

```bash
docker compose down                             # stack fully torn down first
ansible-playbook -i inventory.ini playbook.yml -v < /dev/null
# → PLAY RECAP: ok=10  changed=1   (run-cold.txt — built/started from nothing)

ansible-playbook -i inventory.ini playbook.yml -v < /dev/null
# → PLAY RECAP: ok=10  changed=0   (run-idempotent.txt — same desired state, nothing to do)
```

That second number — `changed=0` on the warm rerun — is the actual test, and it's
worth being precise about why. `ok=10` on both runs only tells you nothing
errored; a non-idempotent playbook can produce `ok=10 changed=10` on every single
run forever and still "pass" by that measure alone, quietly rewriting files or
restarting containers it didn't need to touch every time it's invoked. `changed=0`
on the second run is what actually proves each task compared desired state
against real state and correctly concluded there was nothing to do — that's the
whole promise of Ansible, demonstrated rather than assumed.

**The real bug hit along the way**, worth including because it's a genuinely
common environment problem, not a code bug: `ansible-playbook` failed
immediately with `ERROR: Ansible requires blocking IO on stdin/stdout/stderr.
Non-blocking file handles detected`. The root cause was a non-blocking stdin pipe
in the shell that launched it — Ansible's forking model requires blocking I/O and
refuses to run otherwise. The fix was redirecting stdin from `/dev/null`
(`ansible-playbook ... playbook.yml -v < /dev/null`), which is a real, documented
Ansible constraint, not something papered over with a flag that suppresses the
check. Separately, the first `ansible-galaxy collection install
community.docker` hit a transient `504 Gateway Timeout` against Galaxy's API and
succeeded on retry — worth logging as an external-service flake, not a bug in
this repo's code, and a reminder that a fully air-gapped environment would need
that collection pre-vendored rather than fetched at run time.

**Honest gap on scope**: the target here is `localhost`
(`ansible_connection=local`), because this environment has no second machine to
manage over real SSH. The `inventory.ini` structure and role layout are written
exactly as they would be for N remote hosts, and the only change needed to point
this at a real fleet is swapping `ansible_connection=local` for SSH-reachable
hosts — but that swap has not actually been made or tested here. That's a real
limitation, named plainly rather than implied away by the fact that the mechanics
(modules, idempotency, handlers, `uri` polling) are proven for real against a
real Docker Engine.

## 6. Terraform + Ansible together

This split gets asked about directly in interviews, so it's worth being able to
answer it in one crisp sentence and then back it up: **Terraform answers "does
the infrastructure exist, in the shape I declared" — Ansible answers "is the
right software deployed and configured on it, correctly, every single time I
check."**

Concretely: Terraform creates the VPC, the EC2 instance or EKS node group, the S3
bucket, the IAM role — objects that either exist or don't, with attributes that
either match the declared config or don't. It has almost nothing to say about
what's running *inside* that EC2 instance once it boots — that's a different kind
of question, answered by a different kind of tool with a different execution
model (SSH-driven, idempotent module runs against a live OS) rather than
provider-API resource lifecycle management.

Chained in practice: Terraform provisions the instance and, via an output, hands
Ansible the IP address or a dynamic-inventory-discoverable tag; Ansible then
configures it — installs packages, renders config files from templates, starts
and enables services, and (as in this repo) verifies the result actually works
via real HTTP checks, not just "the playbook exited 0." Terraform is not built to
re-run daily against a fleet checking "is nginx still configured correctly" —
that's exactly Ansible's job, and it's the reason a mature pipeline uses both
rather than trying to stretch `local-exec`/`remote-exec` provisioners into doing
Ansible's job, or trying to make Ansible provision cloud resources it has modules
for but that Terraform's plan/state model handles far more safely.

## 7. Day-one checklist for this zone

1. Find every `.tf` file in the repo (`find . -name '*.tf'`) and read `backend.tf`
   first — before anything else, know where state lives and who can read/write it.
2. Identify the state backend concretely: which S3 bucket (or equivalent), is it
   versioned and encrypted, which DynamoDB table (or lock mechanism) backs it,
   and which IAM principals/roles can access either.
3. Run `terraform init` and `terraform plan` against the current backend and
   compare the plan's proposed changes to zero — any non-empty plan on code
   nobody touched is drift, and drift is the first thing to explain, not ignore.
4. Read every `variables.tf` for undocumented or dangerously-defaulted inputs
   (a `public_access = true` default is a review finding, not a footnote).
5. Confirm what `tfsec`/`checkov`/equivalent scanning actually runs in CI, on
   what trigger, and whether any findings are excluded — read the exclusion
   comments, don't just trust the exclusion exists for a good reason.
6. Inventory every Ansible playbook and role that exists
   (`find . -name '*.yml' -path '*playbook*'`, `ls roles/`), and for each one,
   find out when it was last run *for real* against a live target — a playbook
   nobody has run in six months is a playbook whose correctness is currently
   unverified, however clean it reads.
7. Check whether any playbook manages actual secrets, and if so, confirm
   `ansible-vault` (or an equivalent external secrets mechanism) is in use — a
   plaintext credential in `group_vars/` is a finding, immediately.
8. Confirm inventory is static or dynamic, and if dynamic, confirm the plugin
   config's filters actually scope to what you think they scope to
   (`ansible-inventory --graph` to check, before trusting it).

## 8. Troubleshooting quick-reference

| Symptom | Cause | Fix |
|---|---|---|
| `Error acquiring the state lock` that never clears | A previous `apply`/`plan` was killed (Ctrl-C, CI job cancelled, laptop closed) mid-run, leaving a stale DynamoDB lock item | Confirm nobody else is actually running Terraform right now, then `terraform force-unlock <LOCK_ID>` — never force-unlock without first verifying the lock is genuinely abandoned |
| `terraform plan` shows unexpected changes on code nobody touched | Real infrastructure drift — a console click-through, a manual `aws` CLI fix during an incident, or another tool (e.g. an autoscaler) mutating a resource Terraform also manages | Investigate before applying; decide whether to `terraform import`/update HCL to match reality, or apply to force reality back to declared state — don't blindly `apply` away someone's incident fix |
| A provider (e.g. `azurerm`) fails to initialize even for resources you don't need | The provider block authenticates during `terraform init`/`configure` regardless of whether `enable_azure`-style variables leave it with zero resources to create — `-var enable_azure=false` alone doesn't prevent the provider from trying to authenticate | Either supply valid (even minimal) credentials for every declared provider, or remove the provider block/module invocation entirely for environments that genuinely have no access to that cloud |
| `ansible-playbook` hangs or fails immediately with a stdin/blocking-IO error | Ansible requires blocking I/O on stdin/stdout/stderr; a non-blocking pipe (common in CI runners, harness shells, some terminal multiplexers) breaks its forking model | Redirect stdin explicitly: `ansible-playbook -i inventory.ini playbook.yml < /dev/null` |
| Ansible fact-gathering (`gathering: implicit`) times out against a host | Host is unreachable (network/security-group/firewall), SSH key mismatch, or Python isn't present on the target | `ansible <host> -m ping` in isolation first to isolate connectivity vs. fact-gathering; set `gather_facts: false` and gather explicitly if you don't need full facts, to fail faster and cheaper |

Zone 6 command recipes — the exact `plan`/`apply`/`import` invocations and the
Ansible idempotency-check pattern — are collected in the book's toolkit appendix
for quick reference during real work.
