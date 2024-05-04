#!/bin/bash

echo "Starting Install"

# Prompt the user for the number of users to create
echo "How many users do you want to create?"
read num_users

# Array to store user details
declare -a users

# Loop to collect user details
for ((i=1; i<=$num_users; i++)); do
    echo "Enter username for User $i:"
    read username
    echo "Enter password for $username:"
    read -s password  # -s flag hides user input
    users+=("$username:$password")  # Store username and password in the array
done

# Get the total size of the disk
disk_size=$(blockdev --getsize64 /dev/sda)  # Replace /dev/sdX with your disk

# Calculate the size of the partitions (512MB for boot, 4% for swap)
boot_partition_size=$((512*1024*1024))  # 512MB in bytes
swap_partition_size=$((disk_size * 4 / 100))

# Create the partitions using the calculated sizes and specify partition types
echo -e "o\nn\np\n1\n\n+${boot_partition_size}B\nt\n82\na\n1\nn\np\n2\n\n+${swap_partition_size}B\nt\n82\n" | fdisk /dev/sda

echo "Do you want a Home Partition? y or n: "
read HomePartitionR

if [[ "$HomePartitionR" =~ ^[Yy](es)?$ ]]; then
    # Calculate the size of the home partition (remaining space after boot and swap partitions)
    home_partition_size=$(((disk_size - boot_partition_size - swap_partition_size) / 2))
    root_partition_size=$((disk_size - boot_partition_size - swap_partition_size - home_partition_size))
    # Create the home partition
    echo -e "n\np\n3\n\n+${root_partition_size}B\nw" | fdisk /dev/sda
    echo -e "n\np\n3\n\n+${home_partition_size}B\nw" | fdisk /dev/sda
    mkfs.ext4 -L HOME /dev/sda4
    mkdir /mnt/home
    mount /dev/disk/by-label/HOME /mnt/home
else
    # If no home partition, create the root partition covering the entire remaining space
    root_partition_size=$((disk_size - boot_partition_size - swap_partition_size))

    echo -e "n\np\n3\n\n+${root_partition_size}B\nw" | fdisk /dev/sda
fi

mkfs.ext4 -L ROOT /dev/sda3
mkfs.ext4 -L BOOT /dev/sda1
mkswap -L SWAP /dev/sda2

swapon /dev/disk/by-label/SWAP
mount /dev/disk/by-label/ROOT /mnt
mkdir /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
# (UEFI) mkdir /mnt/boot/efi
# (UEFI) mount /dev/disk/by-label/ESP /mnt/boot/efi

# Update the system clock
rc-service ntpd start

# Install base system
basestrap /mnt base base-devel openrc elogind-openrc

# Install Kernel
basestrap /mnt linux linux-firmware
fstabgen -U /mnt >> /mnt/etc/fstab

# Chroot Into System
artix-chroot /mnt

# Add Users
for user in "${users[@]}"; do
    username=$(echo "$user" | cut -d ":" -f 1)
    password=$(echo "$user" | cut -d ":" -f 2)
    useradd -m -G wheel -s /bin/bash "$username"  # Add user to 'wheel' group and set shell to bash
    echo "$username:$password" | chpasswd  # Set password for the user
done