#!/bin/bash
# 修复 susfs 补丁应用失败的脚本

cd $GITHUB_WORKSPACE/kernel_workspace/android-kernel

echo "=== 修复 fs/namespace.c ==="

# 检查 fs/namespace.c 的当前内容，手动添加需要的代码
# 找到 #include 部分，添加 susfs_def.h
if ! grep -q "susfs_def.h" fs/namespace.c; then
    sed -i '/#include <linux\/task_work.h>/a #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif' fs/namespace.c
fi

# 添加 extern 声明
if ! grep -q "susfs_is_current_ksu_domain" fs/namespace.c; then
    sed -i '/#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT/a extern bool susfs_is_current_ksu_domain(void);\nextern bool susfs_is_sdcard_android_data_decrypted __read_mostly;\n\n#define CL_COPY_MNT_NS BIT(25)\n\nstatic DEFINE_IDA(susfs_mnt_id_ida);\nstatic DEFINE_IDA(susfs_mnt_group_ida);\n' fs/namespace.c
fi

# 修复 mnt_free_id 函数
if grep -q "static void mnt_free_id(struct mount \*mnt)" fs/namespace.c; then
    cat > /tmp/mnt_free_id_patch << 'EOF'
static void mnt_free_id(struct mount *mnt)
{
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (mnt->mnt_id >= DEFAULT_KSU_MNT_ID) {
		ida_free(&susfs_mnt_id_ida, mnt->mnt_id);
		return;
	}

	if (mnt->mnt.mnt_flags & VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT) {
		return;
	}

#endif

	ida_free(&mnt_id_ida, mnt->mnt_id);
}
EOF
    # 替换函数
    sed -i '/^static void mnt_free_id/,/^}/c\' fs/namespace.c < /tmp/mnt_free_id_patch
fi

echo "=== 修复 fs/proc/task_mmu.c ==="

# 修复 pagemap_read 函数中的代码
if grep -q "static ssize_t pagemap_read" fs/proc/task_mmu.c; then
    # 在 pagemap_read 函数开头添加必要的变量声明
    sed -i '/^static ssize_t pagemap_read(struct file \*file, char __user \*buf,/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\tstruct vm_area_struct *vma;\n#endif' fs/proc/task_mmu.c
    
    # 在 walk_page_range 调用后添加 sus_map 检查
    sed -i '/ret = walk_page_range(start_vaddr, end, &pagemap_walk);/a #ifdef CONFIG_KSU_SUSFS_SUS_MAP\n\t\tvma = find_vma(mm, start_vaddr);\n\t\tif (vma && vma->vm_file) {\n\t\t\tstruct inode *inode = file_inode(vma->vm_file);\n\t\t\tif (SUSFS_IS_INODE_SUS_MAP(inode)) {\n\t\t\t\tpm.buffer->pme = 0;\n\t\t\t}\n\t\t}\n#endif' fs/proc/task_mmu.c
fi

echo "=== 修复 fs/proc/cmdline.c ==="

# 修复 cmdline.c 的补丁
cat > /tmp/cmdline_fix << 'EOF'
static int cmdline_proc_show(struct seq_file *m, void *v)
{
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (!susfs_spoof_cmdline_or_bootconfig(m)) {
		seq_putc(m, '\n');
		return 0;
	}
#endif
	seq_puts(m, saved_command_line);
	seq_putc(m, '\n');
	return 0;
}
EOF

# 替换 cmdline_proc_show 函数
sed -i '/^static int cmdline_proc_show/,/^}/c\' fs/proc/cmdline.c < /tmp/cmdline_fix

echo "=== 修复完成 ==="