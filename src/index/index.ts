import {
  ResourceGroupsTaggingAPIClient,
  GetResourcesCommand,
  TagResourcesCommand,
} from "@aws-sdk/client-resource-groups-tagging-api";
import { SNSClient, TagResourceCommand } from "@aws-sdk/client-sns";
import {
  EC2Client,
  DescribeRegionsCommand,
  DescribeInstancesCommand,
  CreateTagsCommand as EC2CreateTagsCommand,
  DescribeSecurityGroupsCommand,
  DescribeSubnetsCommand,
  DescribeVpcsCommand,
} from "@aws-sdk/client-ec2";
import {
  IAMClient,
  ListRolesCommand,
  ListUsersCommand,
  ListPoliciesCommand,
  TagRoleCommand,
  TagUserCommand,
  TagPolicyCommand,
  GetRoleCommand,
  GetUserCommand,
  ListPolicyTagsCommand,
} from "@aws-sdk/client-iam";
import {
  S3Client,
  ListBucketsCommand,
  GetBucketTaggingCommand,
  PutBucketTaggingCommand,
  GetBucketLocationCommand,
} from "@aws-sdk/client-s3";
import {
  RDSClient,
  DescribeDBInstancesCommand,
  DescribeDBClustersCommand,
  AddTagsToResourceCommand as RDSAddTagsCommand,
  ListTagsForResourceCommand as RDSListTagsCommand,
} from "@aws-sdk/client-rds";
import {
  LambdaClient,
  ListFunctionsCommand,
  ListTagsCommand as LambdaListTagsCommand,
  TagResourceCommand as LambdaTagResourceCommand,
} from "@aws-sdk/client-lambda";
import {
  EKSClient,
  ListClustersCommand,
  DescribeClusterCommand,
  TagResourceCommand as EKSTagResourceCommand,
} from "@aws-sdk/client-eks";
import {
  LightsailClient,
  GetInstancesCommand as LightsailGetInstancesCommand,
  GetRelationalDatabasesCommand,
  GetLoadBalancersCommand as LightsailGetLoadBalancersCommand,
  GetDisksCommand,
  GetBucketsCommand as LightsailGetBucketsCommand,
  TagResourceCommand as LightsailTagResourceCommand,
} from "@aws-sdk/client-lightsail";
import { STSClient, GetCallerIdentityCommand } from "@aws-sdk/client-sts";

// Tags that will be applied to all resources - Update as needed
const newTags: Record<string, string> = {
  Owner: "",
  ApplicationOwner: "",
  CostAllocation: "International",
  CostRegion: "International",
  Environment: "Production",
  Product: "",
};

// When true:  apply tags to ALL discovered resources, even those that already have all required tags.
// When false: only tag resources that are missing at least one required tag.
const tagExistingResourcesWithTags = true;

interface ResourceWithTags {
  resourceArn: string;
  resourceId?: string;
  resourceType: string;
  existingTags: Record<string, string>;
  region: string;
}

interface TaggingResult {
  success: number;
  failed: number;
  errors: string[];
}

const EnvConfig: Record<string, string | undefined> = {
  accessKeyId: "",
  secretAccessKey: "",
  region: undefined,
};

// Cached account ID to avoid multiple STS calls
let cachedAccountId: string | null = null;

/**
 * Gets the AWS account ID using STS
 */
async function getAccountId(): Promise<string> {
  if (cachedAccountId) {
    return cachedAccountId;
  }

  const stsClient = new STSClient({
    region: EnvConfig.region || "us-east-1",
  });

  try {
    const command = new GetCallerIdentityCommand({});
    const response = await stsClient.send(command);
    cachedAccountId = response.Account || "unknown";
    return cachedAccountId;
  } catch (error) {
    console.error("Error getting account ID:", error);
    return "unknown";
  }
}

/**
 * Gets all AWS regions from the EC2 service.
 */
async function getAllRegions(): Promise<string[]> {
  const ec2Client = new EC2Client({
    region: EnvConfig.region,
  });
  const command = new DescribeRegionsCommand({});
  const response = await ec2Client.send(command);
  return (
    response.Regions?.map((region) => region.RegionName || "").filter(
      Boolean
    ) || []
  );
}

/**
 * Gets resources that don't have any of the required tags or are missing some tags
 */
function getResourcesNeedingTags(
  resources: ResourceWithTags[]
): ResourceWithTags[] {
  const requiredTagKeys = Object.keys(newTags);

  return resources.filter((resource) => {
    const existingTagKeys = Object.keys(resource.existingTags);
    const missingTags = requiredTagKeys.filter(
      (tagKey) => !existingTagKeys.includes(tagKey)
    );
    return missingTags.length > 0;
  });
}

/**
 * Gets all taggable resources using Resource Groups Tagging API
 */
async function getResourcesFromTaggingAPI(
  region: string
): Promise<ResourceWithTags[]> {
  const taggingClient = new ResourceGroupsTaggingAPIClient({
    region,
  });

  const resources: ResourceWithTags[] = [];
  let paginationToken: string | undefined;

  do {
    try {
      const command = new GetResourcesCommand({
        PaginationToken: paginationToken,
      });
      const response = await taggingClient.send(command);

      if (response.ResourceTagMappingList) {
        for (const mapping of response.ResourceTagMappingList) {
          if (mapping.ResourceARN) {
            const tags: Record<string, string> = {};
            if (mapping.Tags) {
              for (const tag of mapping.Tags) {
                if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                  tags[tag.Key] = tag.Value;
                }
              }
            }

            resources.push({
              resourceArn: mapping.ResourceARN,
              resourceType: mapping.ResourceARN.split(":")[2] || "unknown",
              existingTags: tags,
              region: region,
            });
          }
        }
      }
      paginationToken = response.PaginationToken;
    } catch (error) {
      console.error(
        `Error fetching resources from Tagging API in ${region}:`,
        error
      );
      break;
    }
  } while (paginationToken);

  return resources;
}

/**
 * Gets S3 buckets (global resource)
 */
async function getS3Buckets(): Promise<ResourceWithTags[]> {
  const s3Client = new S3Client({
    region: EnvConfig.region,
  });

  const resources: ResourceWithTags[] = [];

  try {
    const listCommand = new ListBucketsCommand({});
    const listResponse = await s3Client.send(listCommand);

    if (listResponse.Buckets) {
      for (const bucket of listResponse.Buckets) {
        if (bucket.Name) {
          try {
            let bucketRegion = EnvConfig.region || "us-east-1";
            try {
              const locationCommand = new GetBucketLocationCommand({
                Bucket: bucket.Name,
              });
              const locationResponse = await s3Client.send(locationCommand);
              bucketRegion =
                locationResponse.LocationConstraint || EnvConfig.region || "us-east-1";
              if (!bucketRegion || bucketRegion === "null") {
                bucketRegion = EnvConfig.region || "us-east-1";
              }
            } catch (locationError) {
              console.error(
                `Error getting bucket location for ${bucket.Name}:`,
                locationError
              );
            }

            const regionS3Client = new S3Client({
              region: bucketRegion,
            });

            const tags: Record<string, string> = {};
            try {
              const tagCommand = new GetBucketTaggingCommand({
                Bucket: bucket.Name,
              });
              const tagResponse = await regionS3Client.send(tagCommand);

              if (tagResponse.TagSet) {
                for (const tag of tagResponse.TagSet) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }
            } catch (tagError: any) {
              if (tagError.name !== "NoSuchTagSet") {
                console.error(
                  `Error getting tags for bucket ${bucket.Name}:`,
                  tagError
                );
              }
            }

            resources.push({
              resourceArn: `arn:aws:s3:::${bucket.Name}`,
              resourceId: bucket.Name,
              resourceType: "s3-bucket",
              existingTags: tags,
              region: bucketRegion,
            });
          } catch (error) {
            console.error(`Error processing bucket ${bucket.Name}:`, error);
          }
        }
      }
    }
  } catch (error) {
    console.error("Error fetching S3 buckets:", error);
  }

  return resources;
}

/**
 * Gets EC2 instances in a region
 */
async function getEC2Instances(region: string): Promise<ResourceWithTags[]> {
  const ec2Client = new EC2Client({ region });

  const resources: ResourceWithTags[] = [];
  let nextToken: string | undefined;
  const accountId = await getAccountId();

  do {
    try {
      const command = new DescribeInstancesCommand({ NextToken: nextToken });
      const response = await ec2Client.send(command);

      if (response.Reservations) {
        for (const reservation of response.Reservations) {
          if (reservation.Instances) {
            for (const instance of reservation.Instances) {
              if (
                instance.InstanceId &&
                instance.State?.Name !== "terminated"
              ) {
                const tags: Record<string, string> = {};
                if (instance.Tags) {
                  for (const tag of instance.Tags) {
                    if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                      tags[tag.Key] = tag.Value;
                    }
                  }
                }

                resources.push({
                  resourceArn: `arn:aws:ec2:${region}:${accountId}:instance/${instance.InstanceId}`,
                  resourceId: instance.InstanceId,
                  resourceType: "ec2",
                  existingTags: tags,
                  region,
                });
              }
            }
          }
        }
      }
      nextToken = response.NextToken;
    } catch (error) {
      console.error(`Error fetching EC2 instances in ${region}:`, error);
      break;
    }
  } while (nextToken);

  return resources;
}

/**
 * Gets Security Groups in a region
 */
async function getSecurityGroups(region: string): Promise<ResourceWithTags[]> {
  const ec2Client = new EC2Client({ region });

  const resources: ResourceWithTags[] = [];
  let nextToken: string | undefined;
  const accountId = await getAccountId();

  do {
    try {
      const command = new DescribeSecurityGroupsCommand({
        NextToken: nextToken,
      });
      const response = await ec2Client.send(command);

      if (response.SecurityGroups) {
        for (const sg of response.SecurityGroups) {
          if (sg.GroupId) {
            const tags: Record<string, string> = {};
            if (sg.Tags) {
              for (const tag of sg.Tags) {
                if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                  tags[tag.Key] = tag.Value;
                }
              }
            }

            resources.push({
              resourceArn: `arn:aws:ec2:${region}:${accountId}:security-group/${sg.GroupId}`,
              resourceId: sg.GroupId,
              resourceType: "security-group",
              existingTags: tags,
              region,
            });
          }
        }
      }
      nextToken = response.NextToken;
    } catch (error) {
      console.error(`Error fetching Security Groups in ${region}:`, error);
      break;
    }
  } while (nextToken);

  return resources;
}

/**
 * Gets Subnets in a region
 */
async function getSubnets(region: string): Promise<ResourceWithTags[]> {
  const ec2Client = new EC2Client({ region });

  const resources: ResourceWithTags[] = [];
  let nextToken: string | undefined;
  const accountId = await getAccountId();

  do {
    try {
      const command = new DescribeSubnetsCommand({ NextToken: nextToken });
      const response = await ec2Client.send(command);

      if (response.Subnets) {
        for (const subnet of response.Subnets) {
          if (subnet.SubnetId) {
            const tags: Record<string, string> = {};
            if (subnet.Tags) {
              for (const tag of subnet.Tags) {
                if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                  tags[tag.Key] = tag.Value;
                }
              }
            }

            resources.push({
              resourceArn: `arn:aws:ec2:${region}:${accountId}:subnet/${subnet.SubnetId}`,
              resourceId: subnet.SubnetId,
              resourceType: "subnet",
              existingTags: tags,
              region,
            });
          }
        }
      }
      nextToken = response.NextToken;
    } catch (error) {
      console.error(`Error fetching Subnets in ${region}:`, error);
      break;
    }
  } while (nextToken);

  return resources;
}

/**
 * Gets VPCs in a region
 */
async function getVPCs(region: string): Promise<ResourceWithTags[]> {
  const ec2Client = new EC2Client({ region });

  const resources: ResourceWithTags[] = [];
  let nextToken: string | undefined;
  const accountId = await getAccountId();

  do {
    try {
      const command = new DescribeVpcsCommand({ NextToken: nextToken });
      const response = await ec2Client.send(command);

      if (response.Vpcs) {
        for (const vpc of response.Vpcs) {
          if (vpc.VpcId) {
            const tags: Record<string, string> = {};
            if (vpc.Tags) {
              for (const tag of vpc.Tags) {
                if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                  tags[tag.Key] = tag.Value;
                }
              }
            }

            resources.push({
              resourceArn: `arn:aws:ec2:${region}:${accountId}:vpc/${vpc.VpcId}`,
              resourceId: vpc.VpcId,
              resourceType: "vpc",
              existingTags: tags,
              region,
            });
          }
        }
      }
      nextToken = response.NextToken;
    } catch (error) {
      console.error(`Error fetching VPCs in ${region}:`, error);
      break;
    }
  } while (nextToken);

  return resources;
}

/**
 * Gets IAM roles (global resource)
 */
async function getIAMRoles(): Promise<ResourceWithTags[]> {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      const command = new ListRolesCommand({ Marker: marker });
      const response = await iamClient.send(command);

      if (response.Roles) {
        for (const role of response.Roles) {
          if (role.RoleName && role.Arn) {
            try {
              const getRoleCommand = new GetRoleCommand({
                RoleName: role.RoleName,
              });
              const roleDetails = await iamClient.send(getRoleCommand);

              const tags: Record<string, string> = {};
              if (roleDetails.Role?.Tags) {
                for (const tag of roleDetails.Role.Tags) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }

              resources.push({
                resourceArn: role.Arn,
                resourceId: role.RoleName,
                resourceType: "iam-role",
                existingTags: tags,
                region: "global",
              });
            } catch (error) {
              console.error(
                `Error getting role details for ${role.RoleName}:`,
                error
              );
            }
          }
        }
      }
      marker = response.Marker;
    } catch (error) {
      console.error("Error fetching IAM roles:", error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets IAM users (global resource)
 */
async function getIAMUsers(): Promise<ResourceWithTags[]> {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      const command = new ListUsersCommand({ Marker: marker });
      const response = await iamClient.send(command);

      if (response.Users) {
        for (const user of response.Users) {
          if (user.UserName && user.Arn) {
            try {
              const getUserCommand = new GetUserCommand({
                UserName: user.UserName,
              });
              const userDetails = await iamClient.send(getUserCommand);

              const tags: Record<string, string> = {};
              if (userDetails.User?.Tags) {
                for (const tag of userDetails.User.Tags) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }

              resources.push({
                resourceArn: user.Arn,
                resourceId: user.UserName,
                resourceType: "iam-user",
                existingTags: tags,
                region: "global",
              });
            } catch (error) {
              console.error(
                `Error getting user details for ${user.UserName}:`,
                error
              );
            }
          }
        }
      }
      marker = response.Marker;
    } catch (error) {
      console.error("Error fetching IAM users:", error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets customer-managed IAM policies (global resource)
 */
async function getIAMPolicies(): Promise<ResourceWithTags[]> {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      // Scope "Local" returns only customer-managed policies (not AWS-managed)
      const command = new ListPoliciesCommand({
        Scope: "Local",
        Marker: marker,
      });
      const response = await iamClient.send(command);

      if (response.Policies) {
        for (const policy of response.Policies) {
          if (policy.PolicyName && policy.Arn) {
            try {
              const tagsCommand = new ListPolicyTagsCommand({
                PolicyArn: policy.Arn,
              });
              const tagsResponse = await iamClient.send(tagsCommand);

              const tags: Record<string, string> = {};
              if (tagsResponse.Tags) {
                for (const tag of tagsResponse.Tags) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }

              resources.push({
                resourceArn: policy.Arn,
                resourceId: policy.PolicyName,
                resourceType: "iam-policy",
                existingTags: tags,
                region: "global",
              });
            } catch (error) {
              console.error(
                `Error getting tags for policy ${policy.PolicyName}:`,
                error
              );
            }
          }
        }
      }
      marker = response.Marker;
    } catch (error) {
      console.error("Error fetching IAM policies:", error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets RDS DB instances in a region
 */
async function getRDSInstances(region: string): Promise<ResourceWithTags[]> {
  const rdsClient = new RDSClient({ region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      const command = new DescribeDBInstancesCommand({ Marker: marker });
      const response = await rdsClient.send(command);

      if (response.DBInstances) {
        for (const db of response.DBInstances) {
          if (db.DBInstanceIdentifier && db.DBInstanceArn) {
            try {
              const tagsCommand = new RDSListTagsCommand({
                ResourceName: db.DBInstanceArn,
              });
              const tagsResponse = await rdsClient.send(tagsCommand);

              const tags: Record<string, string> = {};
              if (tagsResponse.TagList) {
                for (const tag of tagsResponse.TagList) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }

              resources.push({
                resourceArn: db.DBInstanceArn,
                resourceId: db.DBInstanceIdentifier,
                resourceType: "rds-instance",
                existingTags: tags,
                region,
              });
            } catch (error) {
              console.error(
                `Error getting tags for RDS instance ${db.DBInstanceIdentifier}:`,
                error
              );
            }
          }
        }
      }
      marker = response.Marker;
    } catch (error) {
      console.error(`Error fetching RDS instances in ${region}:`, error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets RDS Aurora clusters in a region
 */
async function getRDSClusters(region: string): Promise<ResourceWithTags[]> {
  const rdsClient = new RDSClient({ region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      const command = new DescribeDBClustersCommand({ Marker: marker });
      const response = await rdsClient.send(command);

      if (response.DBClusters) {
        for (const cluster of response.DBClusters) {
          if (cluster.DBClusterIdentifier && cluster.DBClusterArn) {
            try {
              const tagsCommand = new RDSListTagsCommand({
                ResourceName: cluster.DBClusterArn,
              });
              const tagsResponse = await rdsClient.send(tagsCommand);

              const tags: Record<string, string> = {};
              if (tagsResponse.TagList) {
                for (const tag of tagsResponse.TagList) {
                  if (tag.Key && tag.Value && !tag.Key.startsWith("aws:")) {
                    tags[tag.Key] = tag.Value;
                  }
                }
              }

              resources.push({
                resourceArn: cluster.DBClusterArn,
                resourceId: cluster.DBClusterIdentifier,
                resourceType: "rds-cluster",
                existingTags: tags,
                region,
              });
            } catch (error) {
              console.error(
                `Error getting tags for RDS cluster ${cluster.DBClusterIdentifier}:`,
                error
              );
            }
          }
        }
      }
      marker = response.Marker;
    } catch (error) {
      console.error(`Error fetching RDS clusters in ${region}:`, error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets Lambda functions in a region
 */
async function getLambdaFunctions(region: string): Promise<ResourceWithTags[]> {
  const lambdaClient = new LambdaClient({ region });

  const resources: ResourceWithTags[] = [];
  let marker: string | undefined;

  do {
    try {
      const command = new ListFunctionsCommand({ Marker: marker });
      const response = await lambdaClient.send(command);

      if (response.Functions) {
        for (const fn of response.Functions) {
          if (fn.FunctionName && fn.FunctionArn) {
            try {
              const tagsCommand = new LambdaListTagsCommand({
                Resource: fn.FunctionArn,
              });
              const tagsResponse = await lambdaClient.send(tagsCommand);

              const tags: Record<string, string> = {};
              if (tagsResponse.Tags) {
                for (const [key, value] of Object.entries(tagsResponse.Tags)) {
                  if (!key.startsWith("aws:")) {
                    tags[key] = value as string;
                  }
                }
              }

              resources.push({
                resourceArn: fn.FunctionArn,
                resourceId: fn.FunctionName,
                resourceType: "lambda",
                existingTags: tags,
                region,
              });
            } catch (error) {
              console.error(
                `Error getting tags for Lambda function ${fn.FunctionName}:`,
                error
              );
            }
          }
        }
      }
      marker = response.NextMarker;
    } catch (error) {
      console.error(`Error fetching Lambda functions in ${region}:`, error);
      break;
    }
  } while (marker);

  return resources;
}

/**
 * Gets EKS (Kubernetes) clusters in a region
 */
async function getEKSClusters(region: string): Promise<ResourceWithTags[]> {
  const eksClient = new EKSClient({ region });
  const accountId = await getAccountId();

  const resources: ResourceWithTags[] = [];
  let nextToken: string | undefined;

  do {
    try {
      const command = new ListClustersCommand({ nextToken });
      const response = await eksClient.send(command);

      if (response.clusters) {
        for (const clusterName of response.clusters) {
          try {
            const describeCommand = new DescribeClusterCommand({
              name: clusterName,
            });
            const describeResponse = await eksClient.send(describeCommand);
            const cluster = describeResponse.cluster;

            if (cluster) {
              const tags: Record<string, string> = {};
              if (cluster.tags) {
                for (const [key, value] of Object.entries(cluster.tags)) {
                  if (!key.startsWith("aws:")) {
                    tags[key] = value as string;
                  }
                }
              }

              const clusterArn =
                cluster.arn ||
                `arn:aws:eks:${region}:${accountId}:cluster/${clusterName}`;

              resources.push({
                resourceArn: clusterArn,
                resourceId: clusterName,
                resourceType: "eks-cluster",
                existingTags: tags,
                region,
              });
            }
          } catch (error) {
            console.error(
              `Error getting details for EKS cluster ${clusterName}:`,
              error
            );
          }
        }
      }
      nextToken = response.nextToken;
    } catch (error) {
      console.error(`Error fetching EKS clusters in ${region}:`, error);
      break;
    }
  } while (nextToken);

  return resources;
}

/**
 * Gets all Lightsail resources in a region (instances, databases, load balancers, disks, buckets)
 */
async function getLightsailResources(
  region: string
): Promise<ResourceWithTags[]> {
  const client = new LightsailClient({ region });
  const resources: ResourceWithTags[] = [];

  // Helper to extract tags from a Lightsail tag list
  const extractTags = (
    rawTags?: { key?: string; value?: string }[]
  ): Record<string, string> => {
    const tags: Record<string, string> = {};
    if (rawTags) {
      for (const tag of rawTags) {
        if (tag.key && !tag.key.startsWith("aws:")) {
          tags[tag.key] = tag.value ?? "";
        }
      }
    }
    return tags;
  };

  // Instances
  try {
    let pageToken: string | undefined;
    do {
      const response = await client.send(
        new LightsailGetInstancesCommand({ pageToken })
      );
      for (const instance of response.instances ?? []) {
        if (instance.name && instance.arn) {
          resources.push({
            resourceArn: instance.arn,
            resourceId: instance.name,
            resourceType: "lightsail-instance",
            existingTags: extractTags(instance.tags),
            region,
          });
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  } catch (error) {
    console.error(`Error fetching Lightsail instances in ${region}:`, error);
  }

  // Relational databases
  try {
    let pageToken: string | undefined;
    do {
      const response = await client.send(
        new GetRelationalDatabasesCommand({ pageToken })
      );
      for (const db of response.relationalDatabases ?? []) {
        if (db.name && db.arn) {
          resources.push({
            resourceArn: db.arn,
            resourceId: db.name,
            resourceType: "lightsail-database",
            existingTags: extractTags(db.tags),
            region,
          });
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  } catch (error) {
    console.error(
      `Error fetching Lightsail databases in ${region}:`,
      error
    );
  }

  // Load balancers
  try {
    let pageToken: string | undefined;
    do {
      const response = await client.send(
        new LightsailGetLoadBalancersCommand({ pageToken })
      );
      for (const lb of response.loadBalancers ?? []) {
        if (lb.name && lb.arn) {
          resources.push({
            resourceArn: lb.arn,
            resourceId: lb.name,
            resourceType: "lightsail-load-balancer",
            existingTags: extractTags(lb.tags),
            region,
          });
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  } catch (error) {
    console.error(
      `Error fetching Lightsail load balancers in ${region}:`,
      error
    );
  }

  // Disks (block storage)
  try {
    let pageToken: string | undefined;
    do {
      const response = await client.send(
        new GetDisksCommand({ pageToken })
      );
      for (const disk of response.disks ?? []) {
        if (disk.name && disk.arn) {
          resources.push({
            resourceArn: disk.arn,
            resourceId: disk.name,
            resourceType: "lightsail-disk",
            existingTags: extractTags(disk.tags),
            region,
          });
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  } catch (error) {
    console.error(`Error fetching Lightsail disks in ${region}:`, error);
  }

  // Buckets (object storage)
  try {
    let pageToken: string | undefined;
    do {
      const response = await client.send(
        new LightsailGetBucketsCommand({ pageToken })
      );
      for (const bucket of response.buckets ?? []) {
        if (bucket.name && bucket.arn) {
          resources.push({
            resourceArn: bucket.arn,
            resourceId: bucket.name,
            resourceType: "lightsail-bucket",
            existingTags: extractTags(bucket.tags),
            region,
          });
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken);
  } catch (error) {
    console.error(`Error fetching Lightsail buckets in ${region}:`, error);
  }

  return resources;
}

/**
 * Tags a resource based on its type
 */
async function tagResource(
  resource: ResourceWithTags,
  retries = 3
): Promise<boolean> {
  const mergedTags = { ...resource.existingTags, ...newTags };

  for (let attempt = 1; attempt <= retries; attempt++) {
    try {
      switch (resource.resourceType) {
        case "ec2":
          await tagEC2Instance(resource, mergedTags);
          break;
        case "security-group":
          await tagEC2Resource(resource, mergedTags);
          break;
        case "subnet":
          await tagEC2Resource(resource, mergedTags);
          break;
        case "vpc":
          await tagEC2Resource(resource, mergedTags);
          break;
        case "iam-role":
          await tagIAMRole(resource, mergedTags);
          break;
        case "iam-user":
          await tagIAMUser(resource, mergedTags);
          break;
        case "iam-policy":
          await tagIAMPolicy(resource, mergedTags);
          break;
        case "s3-bucket":
          await tagS3Bucket(resource, mergedTags);
          break;
        case "rds-instance":
        case "rds-cluster":
          await tagRDSResource(resource, mergedTags);
          break;
        case "lambda":
          await tagLambdaFunction(resource, mergedTags);
          break;
        case "eks-cluster":
          await tagEKSCluster(resource, mergedTags);
          break;
        case "lightsail-instance":
        case "lightsail-database":
        case "lightsail-load-balancer":
        case "lightsail-disk":
        case "lightsail-bucket":
          await tagLightsailResource(resource, mergedTags);
          break;
        case "sns":
          await tagSNSResource(resource, mergedTags);
          break;
        default:
          await tagWithResourceGroupsAPI(resource, mergedTags);
          break;
      }

      console.log(
        `Successfully tagged ${resource.resourceType}: ${resource.resourceArn}`
      );
      return true;
    } catch (error) {
      console.error(
        `Error tagging resource (attempt ${attempt}/${retries}): ${resource.resourceArn}`,
        error
      );

      if (attempt === retries) {
        console.error(
          `Failed to tag resource after ${retries} attempts: ${resource.resourceArn}`
        );
        return false;
      }

      // Exponential backoff
      await new Promise((resolve) =>
        setTimeout(resolve, 1000 * Math.pow(2, attempt - 1))
      );
    }
  }
  return false;
}

/**
 * Tag EC2 instance using EC2 API
 */
async function tagEC2Instance(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const ec2Client = new EC2Client({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new EC2CreateTagsCommand({
    Resources: [resource.resourceId!],
    Tags: tagsArray,
  });

  await ec2Client.send(command);
}

/**
 * Tag any EC2 resource (security groups, subnets, VPCs) using EC2 CreateTags API
 */
async function tagEC2Resource(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const ec2Client = new EC2Client({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new EC2CreateTagsCommand({
    Resources: [resource.resourceId!],
    Tags: tagsArray,
  });

  await ec2Client.send(command);
}

/**
 * Tag IAM Role using IAM API
 */
async function tagIAMRole(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new TagRoleCommand({
    RoleName: resource.resourceId!,
    Tags: tagsArray,
  });

  await iamClient.send(command);
}

/**
 * Tag IAM User using IAM API
 */
async function tagIAMUser(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new TagUserCommand({
    UserName: resource.resourceId!,
    Tags: tagsArray,
  });

  await iamClient.send(command);
}

/**
 * Tag IAM Policy using IAM API
 */
async function tagIAMPolicy(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const iamClient = new IAMClient({ region: EnvConfig.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new TagPolicyCommand({
    PolicyArn: resource.resourceArn,
    Tags: tagsArray,
  });

  await iamClient.send(command);
}

/**
 * Tag S3 bucket using S3 API
 */
async function tagS3Bucket(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const s3Client = new S3Client({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new PutBucketTaggingCommand({
    Bucket: resource.resourceId!,
    Tagging: {
      TagSet: tagsArray,
    },
  });

  await s3Client.send(command);
}

/**
 * Tag RDS instance or cluster using RDS API
 */
async function tagRDSResource(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const rdsClient = new RDSClient({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new RDSAddTagsCommand({
    ResourceName: resource.resourceArn,
    Tags: tagsArray,
  });

  await rdsClient.send(command);
}

/**
 * Tag Lambda function using Lambda API
 */
async function tagLambdaFunction(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const lambdaClient = new LambdaClient({ region: resource.region });

  const command = new LambdaTagResourceCommand({
    Resource: resource.resourceArn,
    Tags: tags,
  });

  await lambdaClient.send(command);
}

/**
 * Tag EKS cluster using EKS API
 */
async function tagEKSCluster(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const eksClient = new EKSClient({ region: resource.region });

  const command = new EKSTagResourceCommand({
    resourceArn: resource.resourceArn,
    tags,
  });

  await eksClient.send(command);
}

/**
 * Tag any Lightsail resource using the Lightsail API.
 * Lightsail tags use lowercase key/value and are identified by resource name.
 */
async function tagLightsailResource(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const lightsailClient = new LightsailClient({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([key, value]) => ({
    key,
    value,
  }));

  const command = new LightsailTagResourceCommand({
    resourceName: resource.resourceId!,
    resourceArn: resource.resourceArn,
    tags: tagsArray,
  });

  await lightsailClient.send(command);
}

/**
 * Tag SNS resource using SNS API
 */
async function tagSNSResource(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const snsClient = new SNSClient({ region: resource.region });

  const tagsArray = Object.entries(tags).map(([Key, Value]) => ({
    Key,
    Value,
  }));

  const command = new TagResourceCommand({
    ResourceArn: resource.resourceArn,
    Tags: tagsArray,
  });

  await snsClient.send(command);
}

/**
 * Tag resource using Resource Groups Tagging API
 */
async function tagWithResourceGroupsAPI(
  resource: ResourceWithTags,
  tags: Record<string, string>
) {
  const taggingClient = new ResourceGroupsTaggingAPIClient({
    region: resource.region === "global" ? EnvConfig.region : resource.region,
  });

  const command = new TagResourcesCommand({
    ResourceARNList: [resource.resourceArn],
    Tags: tags,
  });

  await taggingClient.send(command);
}

/**
 * Get all resources across all regions and services
 */
async function getAllResources(): Promise<ResourceWithTags[]> {
  console.log("Discovering all resources across regions and services...\n");

  const allResources: ResourceWithTags[] = [];
  const regions = await getAllRegions();

  console.log(`Found ${regions.length} regions: ${regions.join(", ")}\n`);

  // Get IAM resources (global - not region-specific)
  console.log("Fetching IAM roles, users, and policies (global)...");
  try {
    const [iamRoles, iamUsers, iamPolicies] = await Promise.all([
      getIAMRoles(),
      getIAMUsers(),
      getIAMPolicies(),
    ]);
    allResources.push(...iamRoles, ...iamUsers, ...iamPolicies);
    console.log(
      `Found ${iamRoles.length} IAM roles, ${iamUsers.length} IAM users, ${iamPolicies.length} IAM policies\n`
    );
  } catch (error) {
    console.error("Error fetching IAM resources:", error);
  }

  // Get S3 resources (global listing, but per-bucket region)
  console.log("Fetching S3 buckets (global)...");
  try {
    const s3Buckets = await getS3Buckets();
    allResources.push(...s3Buckets);
    console.log(`Found ${s3Buckets.length} S3 buckets\n`);
  } catch (error) {
    console.error("Error fetching S3 resources:", error);
  }

  // Process each region in parallel batches to avoid throttling
  const REGION_BATCH_SIZE = 5;
  for (let i = 0; i < regions.length; i += REGION_BATCH_SIZE) {
    const regionBatch = regions.slice(i, i + REGION_BATCH_SIZE);

    await Promise.all(
      regionBatch.map(async (region) => {
        console.log(`Processing region: ${region}`);

        try {
          const [
            taggingApiResources,
            ec2Instances,
            securityGroups,
            subnets,
            vpcs,
            rdsInstances,
            rdsClusters,
            lambdaFunctions,
            eksClusters,
            lightsailResources,
          ] = await Promise.all([
            getResourcesFromTaggingAPI(region),
            getEC2Instances(region),
            getSecurityGroups(region),
            getSubnets(region),
            getVPCs(region),
            getRDSInstances(region),
            getRDSClusters(region),
            getLambdaFunctions(region),
            getEKSClusters(region),
            getLightsailResources(region),
          ]);

          // Merge all resources, de-duplicating by ARN.
          // Explicit fetchers are added after the Tagging API results so they
          // overwrite with enriched data (resourceId, correct resourceType).
          const regionResources = new Map<string, ResourceWithTags>();

          [
            ...taggingApiResources,
            ...ec2Instances,
            ...securityGroups,
            ...subnets,
            ...vpcs,
            ...rdsInstances,
            ...rdsClusters,
            ...lambdaFunctions,
            ...eksClusters,
            ...lightsailResources,
          ].forEach((resource) => {
            regionResources.set(resource.resourceArn, resource);
          });

          const uniqueRegionResources = Array.from(regionResources.values());
          allResources.push(...uniqueRegionResources);

          console.log(
            `  Found ${uniqueRegionResources.length} unique resources in ${region} ` +
              `(EC2: ${ec2Instances.length}, SGs: ${securityGroups.length}, ` +
              `Subnets: ${subnets.length}, VPCs: ${vpcs.length}, ` +
              `RDS: ${rdsInstances.length + rdsClusters.length}, ` +
              `Lambda: ${lambdaFunctions.length}, EKS: ${eksClusters.length}, ` +
              `Lightsail: ${lightsailResources.length})`
          );
        } catch (error) {
          console.error(`Error processing region ${region}:`, error);
        }
      })
    );
  }

  console.log(`\nTotal resources discovered: ${allResources.length}`);
  return allResources;
}

/**
 * Main processing function
 */
async function processAllResources() {
  const startTime = Date.now();
  console.log("Starting comprehensive AWS resource tagging process...\n");

  try {
    const allResources = await getAllResources();

    const resourcesToTag = tagExistingResourcesWithTags
      ? allResources
      : getResourcesNeedingTags(allResources);

    console.log(
      tagExistingResourcesWithTags
        ? `\nTagging all ${resourcesToTag.length} discovered resources (tagExistingResourcesWithTags = true)`
        : `\nResources missing tags: ${resourcesToTag.length} out of ${allResources.length}`
    );

    if (resourcesToTag.length === 0) {
      console.log("All resources are already properly tagged!");
      return;
    }

    // Group resources by type for reporting
    const resourcesByType = resourcesToTag.reduce((acc, resource) => {
      acc[resource.resourceType] = (acc[resource.resourceType] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    console.log("\nResources to tag by type:");
    Object.entries(resourcesByType).forEach(([type, count]) => {
      console.log(`  - ${type}: ${count}`);
    });
    console.log();

    let successCount = 0;
    let failureCount = 0;
    const errors: string[] = [];

    for (let i = 0; i < resourcesToTag.length; i++) {
      const resource = resourcesToTag[i];
      const progress = `[${i + 1}/${resourcesToTag.length}]`;

      console.log(
        `${progress} Tagging ${resource.resourceType}: ${
          resource.resourceId || resource.resourceArn
        }`
      );

      const success = await tagResource(resource);
      if (success) {
        successCount++;
      } else {
        failureCount++;
        errors.push(`Failed to tag: ${resource.resourceArn}`);
      }

      // Small delay to avoid API rate limiting
      if (i < resourcesToTag.length - 1) {
        await new Promise((resolve) => setTimeout(resolve, 100));
      }
    }

    const endTime = Date.now();
    const duration = ((endTime - startTime) / 1000).toFixed(2);

    console.log("\n" + "=".repeat(60));
    console.log("TAGGING SUMMARY");
    console.log("=".repeat(60));
    console.log(`Successfully tagged: ${successCount} resources`);
    console.log(`Failed to tag:       ${failureCount} resources`);
    console.log(`Total execution time: ${duration} seconds`);

    if (errors.length > 0) {
      console.log("\nFailed resources:");
      errors.forEach((error) => console.log(`  - ${error}`));
    }

    console.log("\nTagging process completed!");
  } catch (error) {
    console.error("\nCritical error in tagging process:", error);
    process.exit(1);
  }
}

async function loadEnvironmentVariables() {
  EnvConfig.region = process.env.AWS_REGION ?? EnvConfig.region;
  console.log(`Using AWS region: ${EnvConfig.region}`);
  console.log("Using IAM role credentials from ECS task role");
}

/**
 * Main entry point
 */
async function main() {
  await loadEnvironmentVariables();
  await processAllResources();
}

main().catch((error) => {
  console.error("Unhandled error:", error);
  process.exit(1);
});
